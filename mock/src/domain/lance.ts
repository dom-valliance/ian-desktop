// A small in-memory Lance. It owns the items, agents and settings, derives everything the client
// must not compute, and settles state through events (ADR 0001, 0003, 0009).
import { z } from 'zod';
import type { zActionRequest, zSettingsPatch } from '../generated/zod.gen.js';
import { MockClock } from './clock.js';
import { buildToday, buildViews, isToConfirm, renderItem, type DeriveContext } from './derive.js';
import { MockError } from './errors.js';
import { EventLog } from './events.js';
import {
  COMMITMENT_BY_ACTIONS,
  COMMITMENT_TO_ACTIONS,
  TASK_ACTIONS,
  alertRecord,
  proposalRecord,
} from './factories.js';
import { DEFAULT_MIN_CLIENT_VERSION, MOCK_CONTRACT_VERSION, PRINCIPAL, worldFor } from './seeds.js';
import { HOUR_MS, MINUTE_MS } from './time.js';
import type {
  Agent,
  AgentsOverview,
  Item,
  ItemRecord,
  Me,
  Scenario,
  SessionHeartbeat,
  Settings,
  Severity,
  Snapshot,
  StreamEvent,
  Today,
  Views,
} from './types.js';

type ActionRequest = z.infer<typeof zActionRequest>;
type SettingsPatch = z.infer<typeof zSettingsPatch>;

export interface LanceOptions {
  clock: MockClock;
  scenario: Scenario;
  /** Delay before the events an action causes; they follow the response (ADR 0009). */
  actionDelayMs: number;
}

export interface RecordedSession extends SessionHeartbeat {
  receivedAt: string;
}

export interface ActionAccepted {
  status: 200 | 202;
  correlationId: string;
}

export interface ItemPage {
  items: Item[];
  nextCursor: string | null;
}

export interface ListQuery {
  kind?: Item['kind'] | undefined;
  horizon?: Item['horizon'] | undefined;
  state?: 'open' | 'to_confirm' | undefined;
  cursor?: string | undefined;
  limit: number;
}

const CURSOR = /^c(\d+)$/;
const MAX_SESSIONS = 1000;
const NEW_ITEM_BASE = 1000;

/** Settings before a scenario loads; the first `loadScenario` replaces them. */
function initialSettings(): Settings {
  return worldFor('normal', new Date(0)).settings;
}

const contentKey = (item: Item): string => JSON.stringify({ ...item, version: 0 });

export class MockLance {
  readonly clock: MockClock;
  readonly log: EventLog;
  readonly sessions: RecordedSession[] = [];
  private scenarioName: Scenario;
  private readonly actionDelayMs: number;
  private records = new Map<string, ItemRecord>();
  private agents = new Map<string, Agent>();
  private settings: Settings = initialSettings();
  private median = 1;
  private inExternalMeeting = false;
  private minClientVersion = DEFAULT_MIN_CLIENT_VERSION;
  private published = { items: new Map<string, string>(), today: '', views: '' };
  private silent = false;
  private counter = NEW_ITEM_BASE;
  private readonly pending = new Set<Promise<void>>();
  /** Items with an accepted action whose events have not all been sent. */
  private readonly inFlight = new Set<string>();
  /** Raised when a scenario loads, so steps scheduled for the old world do nothing. */
  private generation = 0;
  /** The version each departed item last had, so a returning id never restarts at 1. */
  private readonly lastVersion = new Map<string, number>();
  private snoozedAlerts: { record: ItemRecord; until: Date }[] = [];
  private handoffOffered = true;

  constructor(options: LanceOptions) {
    this.clock = options.clock;
    this.log = new EventLog(options.clock);
    this.actionDelayMs = options.actionDelayMs;
    this.scenarioName = options.scenario;
    this.silent = true;
    this.loadScenario(options.scenario);
    this.silent = false;
  }

  get scenario(): Scenario {
    return this.scenarioName;
  }

  get currentMinClientVersion(): string {
    return this.minClientVersion;
  }

  setHandoffOffered(offered: boolean): void {
    this.handoffOffered = offered;
  }

  /** Resolves when every event an earlier action scheduled has been sent. */
  async idle(): Promise<void> {
    while (this.pending.size > 0) await Promise.all([...this.pending]);
  }

  // Reads

  me(): Me {
    return {
      ...PRINCIPAL,
      status: this.settings.paused ? 'paused' : 'active',
      mode: this.settings.mode,
      timeZone: this.settings.timeZone,
      minClientVersion: this.minClientVersion,
      contractVersion: MOCK_CONTRACT_VERSION,
      capabilities: { handoff: this.handoffOffered },
      serverTime: this.clock.now().toISOString(),
    };
  }

  snapshot(): Snapshot {
    const items = this.renderAll();
    return {
      cursor: String(this.log.latestId()),
      serverTime: this.clock.now().toISOString(),
      today: this.buildToday(items),
      views: this.buildViews(items),
      items,
      agents: this.agentsOverview(),
      settings: structuredClone(this.settings),
    };
  }

  today(): Today {
    return this.buildToday(this.renderAll());
  }

  item(id: string): Item | undefined {
    const record = this.records.get(id);
    return record ? this.render(record) : undefined;
  }

  listItems(query: ListQuery): ItemPage {
    const wantConfirm = query.state === 'to_confirm';
    const matching = this.renderAll().filter(
      (item) =>
        isToConfirm(item) === wantConfirm &&
        (query.kind === undefined || item.kind === query.kind) &&
        (query.horizon === undefined || item.horizon === query.horizon),
    );
    let offset = 0;
    if (query.cursor !== undefined) {
      const match = CURSOR.exec(query.cursor);
      if (!match) {
        throw new MockError(
          400,
          'Bad request',
          'cursor must be a nextCursor from an earlier page.',
        );
      }
      offset = Number(match[1]);
    }
    const page = matching.slice(offset, offset + query.limit);
    const next = offset + query.limit;
    return { items: page, nextCursor: next < matching.length ? `c${next}` : null };
  }

  agentsOverview(): AgentsOverview {
    return { agents: structuredClone([...this.agents.values()]), costToday: this.costToday() };
  }

  settingsView(): Settings {
    return structuredClone(this.settings);
  }

  // Scenarios, time and raw events

  loadScenario(scenario: Scenario): void {
    this.scenarioName = scenario;
    this.generation += 1;
    this.inFlight.clear();
    this.snoozedAlerts = [];
    const now = this.clock.now();
    const world = worldFor(scenario, now);
    const before = this.records;
    const incoming = new Map(world.records.map((record) => [record.id, record]));
    const previousSettings = this.settings;
    this.settings = world.settings;
    this.median = world.median;
    this.inExternalMeeting = world.inExternalMeeting;
    const minimumChanged = world.minClientVersion !== this.minClientVersion;
    this.minClientVersion = world.minClientVersion;

    for (const [id, record] of before) {
      if (!incoming.has(id)) this.publishRemoved(record, null, undefined);
    }
    const next = new Map<string, ItemRecord>();
    for (const [id, record] of incoming) {
      const existing = before.get(id);
      const key = contentKey(this.render(record));
      if (existing && this.published.items.get(id) === key) {
        next.set(id, existing);
        continue;
      }
      const prior = existing?.version ?? this.lastVersion.get(id);
      record.version = prior === undefined ? 1 : prior + 1;
      next.set(id, record);
      this.publishItem(record, undefined, existing === undefined && record.kind === 'alert');
    }
    this.records = next;

    const previousAgents = this.agents;
    this.agents = new Map(world.agents.map((agent) => [agent.id, agent]));
    for (const agent of this.agents.values()) {
      if (JSON.stringify(previousAgents.get(agent.id)) !== JSON.stringify(agent)) {
        this.emit({
          type: 'agent.updated',
          agent: structuredClone(agent),
          costToday: this.costToday(),
        });
      }
    }
    if (JSON.stringify(previousSettings) !== JSON.stringify(this.settings)) {
      this.emit({ type: 'settings.updated', settings: structuredClone(this.settings) });
    }
    if (minimumChanged && world.minClientVersion !== DEFAULT_MIN_CLIENT_VERSION) {
      this.emit({
        type: 'client.deprecated',
        minClientVersion: world.minClientVersion,
        message: 'This version of Ian is no longer supported. Update to continue.',
      });
    }
    this.publishAggregates();
  }

  /** Moves time, expires what has expired, and publishes whatever the new time changes. */
  moveClock(move: { set: Date } | { advanceMs: number }): { now: string; events: number } {
    const before = this.log.latestId();
    if ('set' in move) this.clock.set(move.set);
    else this.clock.advance(move.advanceMs);
    this.reconcile();
    return { now: this.clock.now().toISOString(), events: this.log.latestId() - before };
  }

  /** Sends a contract event as given. It does not change the mock's state. */
  emitRaw(event: StreamEvent): number | null {
    if (event.type === 'heartbeat') {
      this.log.publishTransient(event);
      return null;
    }
    return this.log.append(event);
  }

  raiseAlert(recipe: { severity: Severity; title?: string | undefined }): Item {
    const id = this.newId('alrt');
    const record = alertRecord(id, {
      severity: recipe.severity,
      title: recipe.title ?? `Mock ${recipe.severity} alert`,
      alertKind: 'mock_alert',
      alertKindLabel: 'Mock alert',
      explanation: 'Raised by POST /__mock/emit to exercise the alert path.',
      raisedAt: this.clock.now(),
      dedupeKey: `mock:${id}`,
    });
    this.records.set(id, record);
    this.publishItem(record, undefined, true);
    this.publishAggregates();
    return this.render(record);
  }

  raiseProposal(recipe: { title?: string | undefined; expiresInMinutes: number }): Item {
    const id = this.newId('prop');
    const record = proposalRecord(id, {
      title: recipe.title ?? 'Send a short reply to [PERSON A]',
      summary: 'Raised by POST /__mock/emit to exercise the proposal path.',
      actionClass: 'draft_email',
      actionClassLabel: 'Draft email',
      targetSystem: 'graph',
      targetSystemLabel: 'Outlook',
      unit: { id: 'unit_client_a', name: '[CLIENT A]' },
      expiresAt: new Date(this.clock.now().getTime() + recipe.expiresInMinutes * MINUTE_MS),
    });
    this.records.set(id, record);
    this.publishItem(record, undefined, false);
    this.publishAggregates();
    return this.render(record);
  }

  recordSession(heartbeat: SessionHeartbeat): void {
    this.sessions.push({ ...heartbeat, receivedAt: this.clock.now().toISOString() });
    if (this.sessions.length > MAX_SESSIONS) this.sessions.shift();
  }

  // Actions

  runAction(itemId: string, actionId: string, body: ActionRequest): ActionAccepted {
    const record = this.records.get(itemId);
    if (!record) throw new MockError(404, 'Not found', `No open item has the id ${itemId}.`);
    const stale = (detail: string): MockError =>
      new MockError(409, 'Item changed', detail, { item: this.render(record) });
    if (this.inFlight.has(itemId)) {
      throw stale('An action on this item is still being settled. Wait for its events.');
    }
    if (body.version !== record.version) {
      throw stale(`The item is at version ${record.version}, not ${body.version}. Read it again.`);
    }
    const action = record.actions.find((candidate) => candidate.id === actionId);
    if (!action) throw stale(`This item does not offer the action ${actionId} now.`);
    if (action.input === 'until' && body.until === undefined) {
      throw new MockError(400, 'Bad request', `The action ${actionId} needs an until time.`);
    }
    if (action.input === 'until' && body.until !== undefined) {
      if (Date.parse(body.until) <= this.clock.now().getTime()) {
        throw new MockError(400, 'Bad request', 'until must be later than the server time.');
      }
    }

    const correlationId = `corr_01MOCK${String(++this.counter).padStart(12, '0')}`;
    const accepted = (status: 200 | 202): ActionAccepted => ({ status, correlationId });
    const run = (...steps: (() => void)[]): void => {
      this.runSteps(record, steps);
    };
    const finish =
      (step: () => void): (() => void) =>
      () => {
        step();
        this.publishAggregates();
      };

    switch (record.kind) {
      case 'proposal':
        if (actionId === 'approve') {
          run(
            () => {
              record.working = true;
              record.actions = [];
              this.republish(record, correlationId);
              this.publishAggregates();
            },
            () => {
              this.removeProposal(record, this.approvalOutcome(), correlationId, true);
              this.publishAggregates();
            },
          );
          return accepted(202);
        }
        run(
          finish(() => {
            this.removeProposal(record, 'Rejected. Nothing was sent.', correlationId, false);
          }),
        );
        return accepted(200);
      case 'commitment_by':
      case 'commitment_to':
        return this.runCommitmentAction(record, actionId, body, correlationId, run, finish);
      case 'task':
        run(
          finish(() => {
            this.raiseCompleteTask(record, correlationId);
          }),
        );
        return accepted(202);
      case 'alert':
        run(
          finish(() => {
            if (actionId === 'snooze' && body.until !== undefined) {
              this.snoozedAlerts.push({ record, until: new Date(body.until) });
            }
            this.publishRemoved(record, undefined, correlationId);
          }),
        );
        return accepted(200);
    }
  }

  handOff(itemId: string, instruction: string | undefined): ActionAccepted {
    if (!this.handoffOffered) {
      throw new MockError(404, 'Not found', 'This server does not offer Hand to Ian.');
    }
    const record = this.records.get(itemId);
    if (!record) throw new MockError(404, 'Not found', `No open item has the id ${itemId}.`);
    const correlationId = `corr_01MOCK${String(++this.counter).padStart(12, '0')}`;
    this.runSteps(record, [
      () => {
        record.working = true;
        this.republish(record, correlationId);
        this.publishAggregates();
      },
      () => {
        record.working = false;
        this.republish(record, correlationId);
        const id = this.newId('prop');
        const proposal = proposalRecord(id, {
          title: `Ian's next step for: ${record.title}`,
          summary: instruction ?? 'Ian prepared a next step for this item.',
          actionClass: 'draft_email',
          actionClassLabel: 'Draft email',
          targetSystem: 'graph',
          targetSystemLabel: 'Outlook',
          unit: record.unit,
          expiresAt: new Date(this.clock.now().getTime() + 6 * HOUR_MS),
        });
        this.records.set(id, proposal);
        this.publishItem(proposal, correlationId, false);
        this.publishAggregates();
      },
    ]);
    return { status: 202, correlationId };
  }

  // Agents and settings

  setAgentPaused(agentId: string, paused: boolean): Agent {
    const agent = this.agents.get(agentId);
    if (!agent) throw new MockError(404, 'Not found', `No agent has the id ${agentId}.`);
    if (!agent.pausable) {
      throw new MockError(
        403,
        'Outside your scope',
        `${agent.name} is not yours to pause or resume. Ask an administrator.`,
      );
    }
    agent.state = paused ? 'paused' : 'idle';
    agent.nextRunAt = paused
      ? null
      : new Date(this.clock.now().getTime() + 10 * MINUTE_MS).toISOString();
    this.emit({
      type: 'agent.updated',
      agent: structuredClone(agent),
      costToday: this.costToday(),
    });
    return structuredClone(agent);
  }

  patchSettings(patch: SettingsPatch): Settings {
    if (patch.mode === 'live' && this.settings.mode !== 'live' && !this.settings.liveEligible) {
      const when = this.settings.liveOpensAt;
      throw new MockError(
        422,
        'Not eligible to go live',
        when === null
          ? 'Going live is not allowed yet. Stay in dry run.'
          : `Going live opens at ${when}. Stay in dry run until then.`,
      );
    }
    const before = JSON.stringify(this.settings);
    if (patch.quietHours !== undefined) this.settings.quietHours = patch.quietHours;
    if (patch.pushBudgetPerHour !== undefined)
      this.settings.pushBudgetPerHour = patch.pushBudgetPerHour;
    if (patch.mode !== undefined) this.settings.mode = patch.mode;
    if (patch.paused !== undefined) {
      this.settings.paused = patch.paused;
      this.settings.pausedReason = patch.paused ? (patch.pausedReason ?? null) : null;
    } else if (patch.pausedReason !== undefined && this.settings.paused) {
      this.settings.pausedReason = patch.pausedReason;
    }
    // A PATCH that changes nothing answers with the current settings and emits no event.
    if (JSON.stringify(this.settings) !== before) {
      this.emit({ type: 'settings.updated', settings: structuredClone(this.settings) });
      this.publishAggregates();
    }
    return structuredClone(this.settings);
  }

  // Internals

  private runCommitmentAction(
    record: ItemRecord,
    actionId: string,
    body: ActionRequest,
    correlationId: string,
    run: (...steps: (() => void)[]) => void,
    finish: (step: () => void) => () => void,
  ): ActionAccepted {
    const detail = record.detail;
    if (detail.kind !== 'commitment_by' && detail.kind !== 'commitment_to') {
      throw new MockError(500, 'Mock error', 'A commitment record carried another detail.');
    }
    switch (actionId) {
      case 'settle':
        run(
          finish(() => {
            this.publishRemoved(record, 'Settled. Recorded on the ledger.', correlationId);
          }),
        );
        return { status: 200, correlationId };
      case 'dismiss':
        run(
          finish(() => {
            this.publishRemoved(record, 'Dismissed. It will not come back.', correlationId);
          }),
        );
        return { status: 200, correlationId };
      case 'snooze':
        run(
          finish(() => {
            if (body.until !== undefined) record.dueAt = new Date(body.until);
            this.republish(record, correlationId);
          }),
        );
        return { status: 200, correlationId };
      case 'confirm':
        run(
          finish(() => {
            detail.toConfirm = false;
            record.actions =
              record.kind === 'commitment_by' ? COMMITMENT_BY_ACTIONS : COMMITMENT_TO_ACTIONS;
            this.republish(record, correlationId);
          }),
        );
        return { status: 200, correlationId };
      case 'chase':
        run(
          finish(() => {
            detail.chase = { ...detail.chase, state: 'requested' };
            record.actions = record.actions.filter((action) => action.id !== 'chase');
            this.republish(record, correlationId);
            const id = this.newId('prop');
            const proposal = proposalRecord(id, {
              title: `Chase ${detail.counterparty.name} about: ${record.title}`,
              summary: body.note ?? 'A short reminder with the date the commitment was made.',
              actionClass: 'draft_email',
              actionClassLabel: 'Draft email',
              targetSystem: 'graph',
              targetSystemLabel: 'Outlook',
              unit: record.unit,
              expiresAt: new Date(this.clock.now().getTime() + 4 * HOUR_MS),
              follows: { itemId: record.id, purpose: 'chase' },
            });
            this.records.set(id, proposal);
            this.publishItem(proposal, correlationId, false);
          }),
        );
        return { status: 202, correlationId };
      default:
        throw new MockError(409, 'Item changed', `The action ${actionId} is not offered.`, {
          item: this.render(record),
        });
    }
  }

  private raiseCompleteTask(task: ItemRecord, correlationId: string): void {
    task.actions = [];
    task.working = false;
    this.republish(task, correlationId);
    const sourceName =
      task.detail.kind === 'task' && task.detail.source === 'jamie' ? 'Jamie' : 'Notion';
    const id = this.newId('prop');
    const proposal = proposalRecord(id, {
      title: `Mark as complete: ${task.title}`,
      summary: `Mark one task as complete in ${sourceName}.`,
      actionClass: 'complete_task',
      actionClassLabel: 'Complete task',
      targetSystem: sourceName.toLowerCase(),
      targetSystemLabel: sourceName,
      unit: task.unit,
      expiresAt: new Date(this.clock.now().getTime() + 4 * HOUR_MS),
      follows: { itemId: task.id, purpose: 'complete_task' },
    });
    this.records.set(id, proposal);
    this.publishItem(proposal, correlationId, false);
  }

  /** Removes a proposal and settles the item it was raised for. */
  private removeProposal(
    proposal: ItemRecord,
    outcome: string,
    correlationId: string | undefined,
    approved: boolean,
  ): void {
    if (!this.records.has(proposal.id)) return;
    this.publishRemoved(proposal, outcome, correlationId);
    const target = proposal.follows ? this.records.get(proposal.follows.itemId) : undefined;
    if (!proposal.follows || !target) return;
    if (proposal.follows.purpose === 'complete_task') {
      if (approved) {
        const source =
          target.detail.kind === 'task' && target.detail.source === 'jamie' ? 'Jamie' : 'Notion';
        this.publishRemoved(target, `Done. Marked complete in ${source}.`, correlationId);
      } else {
        target.actions = TASK_ACTIONS;
        this.republish(target, correlationId);
      }
      return;
    }
    if (target.detail.kind === 'commitment_by' || target.detail.kind === 'commitment_to') {
      const base = target.kind === 'commitment_by' ? COMMITMENT_BY_ACTIONS : COMMITMENT_TO_ACTIONS;
      const now = this.clock.now().toISOString();
      target.detail.chase = approved
        ? {
            state: 'chased',
            count: target.detail.chase.count + 1,
            lastChasedAt: now,
            nextChaseAt: null,
          }
        : {
            ...target.detail.chase,
            state: target.detail.chase.count > 0 ? 'chased' : 'not_chased',
          };
      target.actions = base;
      this.republish(target, correlationId);
    }
  }

  private approvalOutcome(): string {
    return this.settings.mode === 'live'
      ? 'Approved. Carried out.'
      : 'Approved. Recorded in dry run; nothing was sent.';
  }

  private newId(prefix: 'prop' | 'alrt'): string {
    return `${prefix}_01MOCK${String(++this.counter).padStart(12, '0')}`;
  }

  /**
   * Sends an accepted action's events after the response. The item stays in flight until the last
   * step, and a step does nothing once the item has changed hands or a scenario has loaded.
   */
  private runSteps(record: ItemRecord, steps: (() => void)[]): void {
    this.inFlight.add(record.id);
    const generation = this.generation;
    steps.forEach((step, index) => {
      const last = index === steps.length - 1;
      this.schedule(index + 1, () => {
        if (generation !== this.generation) return;
        try {
          if (this.records.get(record.id) === record) step();
        } finally {
          if (last) this.inFlight.delete(record.id);
        }
      });
    });
  }

  private schedule(multiple: number, step: () => void): void {
    const job = new Promise<void>((resolve) => {
      setTimeout(() => {
        try {
          step();
        } finally {
          resolve();
        }
      }, this.actionDelayMs * multiple);
    });
    this.pending.add(job);
    void job.finally(() => this.pending.delete(job));
  }

  private emit(event: StreamEvent): void {
    if (!this.silent) this.log.append(event);
  }

  private deriveContext(): DeriveContext {
    return {
      now: this.clock.now(),
      timeZone: this.settings.timeZone,
      median: this.median,
      settings: this.settings,
      inExternalMeeting: this.inExternalMeeting,
    };
  }

  private render(record: ItemRecord): Item {
    return renderItem(record, this.clock.now(), this.settings.timeZone);
  }

  private renderAll(): Item[] {
    return [...this.records.values()]
      .map((record) => this.render(record))
      .sort((a, b) => b.pressure - a.pressure || a.id.localeCompare(b.id));
  }

  private buildToday(items: Item[]): Today {
    return buildToday(items, this.deriveContext());
  }

  private buildViews(items: Item[]): Views {
    return buildViews(items, this.agents.size);
  }

  private costToday(): AgentsOverview['costToday'] {
    const costGbp =
      Math.round(
        [...this.agents.values()].reduce((sum, agent) => sum + agent.costTodayGbp, 0) * 100,
      ) / 100;
    const ceilingGbp = this.settings.costCeilingGbp;
    return { costGbp, ceilingGbp, fraction: Math.round((costGbp / ceilingGbp) * 1000) / 1000 };
  }

  /** Emits an upsert for the record as it now renders, and notes what the client holds. */
  private publishItem(
    record: ItemRecord,
    correlationId: string | undefined,
    raised: boolean,
  ): void {
    const item = this.render(record);
    this.published.items.set(record.id, contentKey(item));
    const withCorrelation = correlationId === undefined ? {} : { correlationId };
    this.emit(
      raised
        ? { type: 'alert.raised', item, ...withCorrelation }
        : { type: 'item.upserted', item, ...withCorrelation },
    );
  }

  private republish(record: ItemRecord, correlationId: string | undefined): void {
    if (!this.records.has(record.id)) return;
    record.version += 1;
    this.publishItem(record, correlationId, false);
  }

  /** `outcome` is `undefined` for an alert, which has no outcome line, and `null` for none given. */
  private publishRemoved(
    record: ItemRecord,
    outcome: string | null | undefined,
    correlationId: string | undefined,
  ): void {
    if (!this.records.has(record.id)) return;
    this.lastVersion.set(record.id, record.version);
    this.records.delete(record.id);
    this.published.items.delete(record.id);
    const withCorrelation = correlationId === undefined ? {} : { correlationId };
    if (record.kind === 'alert') {
      this.emit({ type: 'alert.cleared', itemId: record.id, ...withCorrelation });
    } else {
      this.emit({
        type: 'item.removed',
        itemId: record.id,
        outcome: outcome ?? null,
        ...withCorrelation,
      });
    }
  }

  /** Publishes Today and the views when they differ from what open streams last heard. */
  private publishAggregates(): void {
    const items = this.renderAll();
    const today = this.buildToday(items);
    const views = this.buildViews(items);
    const todayKey = JSON.stringify(today);
    const viewsKey = JSON.stringify(views);
    if (todayKey !== this.published.today) {
      this.published.today = todayKey;
      this.emit({ type: 'today.updated', today });
    }
    if (viewsKey !== this.published.views) {
      this.published.views = viewsKey;
      this.emit({ type: 'views.updated', views });
    }
  }

  private reconcile(): void {
    const now = this.clock.now().getTime();
    const awake = this.snoozedAlerts.filter((entry) => entry.until.getTime() <= now);
    this.snoozedAlerts = this.snoozedAlerts.filter((entry) => entry.until.getTime() > now);
    for (const { record } of awake) {
      record.version = (this.lastVersion.get(record.id) ?? record.version) + 1;
      this.records.set(record.id, record);
      this.publishItem(record, undefined, true);
    }
    for (const record of [...this.records.values()]) {
      if (record.detail.kind === 'proposal' && Date.parse(record.detail.expiresAt) <= now) {
        this.removeProposal(record, 'Expired. Nothing was sent.', undefined, false);
      }
    }
    for (const record of this.records.values()) {
      const key = contentKey(this.render(record));
      if (this.published.items.get(record.id) !== key) this.republish(record, undefined);
    }
    this.publishAggregates();
  }
}
