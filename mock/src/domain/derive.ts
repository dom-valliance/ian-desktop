// The part of Lance the client must never compute (ADR 0001, ADR 0009): horizon, pressure,
// attention, the Orbit block, the Pillars field, the lists and the views.
import { metaLine } from './labels.js';
import { DAY_MS, MINUTE_MS, endOfLocalDay, isWithinQuietHours } from './time.js';
import type {
  Attention,
  Horizon,
  Item,
  ItemKind,
  ItemRecord,
  Settings,
  Today,
  Views,
} from './types.js';

export interface DeriveContext {
  now: Date;
  timeZone: string;
  /** The principal's 30-day median of daily open counts, set per scenario, floored at 1. */
  median: number;
  settings: Pick<Settings, 'quietHours'>;
  inExternalMeeting: boolean;
}

const HORIZONS: readonly Horizon[] = ['now', 'week', 'later'];
const KINDS: readonly ItemKind[] = ['proposal', 'commitment_by', 'commitment_to', 'task', 'alert'];
const MAX_UNITS = 4;
const URGENT_WINDOW_MS = 15 * MINUTE_MS;

const round2 = (value: number): number => Math.round(value * 100) / 100;

function deadlineOf(record: ItemRecord): Date | null {
  if (record.detail.kind === 'proposal') return new Date(record.detail.expiresAt);
  return record.dueAt;
}

/** Spec 5.4: now is due today, overdue, P0 or P1, or a proposal expiring today; week is within seven days. */
export function horizonOf(record: ItemRecord, now: Date, timeZone: string): Horizon {
  if (record.severity === 'P0' || record.severity === 'P1') return 'now';
  const deadline = deadlineOf(record);
  if (deadline === null) return 'later';
  if (deadline.getTime() < endOfLocalDay(now, timeZone).getTime()) return 'now';
  if (deadline.getTime() <= now.getTime() + 7 * DAY_MS) return 'week';
  return 'later';
}

const SEVERITY_PRESSURE = { P0: 1, P1: 0.9, P2: 0.55, P3: 0.25 } as const;
const NO_DEADLINE_PRESSURE = 0.1;
const MAX_TIMED_PRESSURE = 0.9;
const DECAY_HOURS = 24;
const OVERDUE_RAMP_HOURS = 240;

/**
 * Pressure from 0 to 1, rounded to two places.
 *
 * - An alert carries its severity weight: P0 1, P1 0.9, P2 0.55, P3 0.25.
 * - Anything with a deadline (a due time, or a proposal's expiry) is 0.9 / (1 + hoursLeft / 24),
 *   so it is 0.9 at the deadline, 0.45 a day out and 0.11 a week out.
 * - Once the deadline has passed it climbs from 0.9 to 1 over ten days overdue.
 * - Anything without a deadline is 0.1.
 */
export function pressureOf(record: ItemRecord, now: Date): number {
  if (record.severity !== undefined) return SEVERITY_PRESSURE[record.severity];
  const deadline = deadlineOf(record);
  if (deadline === null) return NO_DEADLINE_PRESSURE;
  const hoursLeft = (deadline.getTime() - now.getTime()) / 3_600_000;
  if (hoursLeft < 0) {
    return round2(Math.min(1, MAX_TIMED_PRESSURE + (-hoursLeft / OVERDUE_RAMP_HOURS) * 0.1));
  }
  return round2(MAX_TIMED_PRESSURE / (1 + hoursLeft / DECAY_HOURS));
}

/** Spec 6.6. The kill switch and the budget ceiling are not items, so they have no rung here. */
export function attentionOf(record: ItemRecord, now: Date, timeZone: string): Attention {
  if (record.severity === 'P0') return 'stop';
  if (record.severity === 'P1' || record.riskLanguage === true) return 'urgent';
  if (record.detail.kind === 'proposal') {
    const untilExpiry = new Date(record.detail.expiresAt).getTime() - now.getTime();
    return untilExpiry <= URGENT_WINDOW_MS ? 'urgent' : 'needs_you';
  }
  if (record.severity === 'P2') return 'needs_you';
  const { detail } = record;
  if (
    (detail.kind === 'commitment_by' || detail.kind === 'commitment_to') &&
    !detail.toConfirm &&
    record.dueAt !== null
  ) {
    return record.dueAt.getTime() < endOfLocalDay(now, timeZone).getTime()
      ? 'needs_you'
      : 'ambient';
  }
  return 'ambient';
}

export function renderItem(record: ItemRecord, now: Date, timeZone: string): Item {
  const item: Item = {
    id: record.id,
    kind: record.kind,
    title: record.title,
    meta: metaLine(record, now, timeZone),
    unit: record.unit,
    horizon: horizonOf(record, now, timeZone),
    pressure: pressureOf(record, now),
    attention: attentionOf(record, now, timeZone),
    dueAt: record.dueAt === null ? null : record.dueAt.toISOString(),
    working: record.working,
    version: record.version,
    actions: record.actions,
    detail: record.detail,
    links: record.links,
  };
  if (record.severity !== undefined) item.severity = record.severity;
  return item;
}

export function isToConfirm(item: Item): boolean {
  return (
    (item.detail.kind === 'commitment_by' || item.detail.kind === 'commitment_to') &&
    item.detail.toConfirm
  );
}

const byPressure = (a: Item, b: Item): number =>
  b.pressure - a.pressure || a.id.localeCompare(b.id);

function dueTime(item: Item): number {
  return item.dueAt === null ? Number.POSITIVE_INFINITY : Date.parse(item.dueAt);
}

function expiryTime(item: Item): number {
  return item.detail.kind === 'proposal'
    ? Date.parse(item.detail.expiresAt)
    : Number.POSITIVE_INFINITY;
}

const OTHER_UNIT = { id: 'other', name: 'Other' } as const;

/** Today covers open items: alerts in, commitments awaiting confirmation out. */
export function buildToday(allItems: readonly Item[], ctx: DeriveContext): Today {
  const items = allItems.filter((item) => !isToConfirm(item)).sort(byPressure);
  const nowItems = items.filter((item) => item.horizon === 'now');

  const sums = new Map<string, { name: string; total: number }>();
  for (const item of items) {
    if (item.unit.id === OTHER_UNIT.id) continue;
    const entry = sums.get(item.unit.id) ?? { name: item.unit.name, total: 0 };
    entry.total += item.pressure;
    sums.set(item.unit.id, entry);
  }
  const ranked = [...sums.entries()]
    .sort(([, a], [, b]) => b.total - a.total || a.name.localeCompare(b.name))
    .slice(0, MAX_UNITS);
  const columnIds = new Set(ranked.map(([id]) => id));
  const columnOf = (item: Item): string =>
    columnIds.has(item.unit.id) ? item.unit.id : OTHER_UNIT.id;

  const units = ranked.map(([id, entry]) => ({ id, name: entry.name }));
  if (items.some((item) => columnOf(item) === OTHER_UNIT.id)) units.push({ ...OTHER_UNIT });

  const cells: Today['field']['cells'] = [];
  const week: Today['lists']['week'] = [];
  const later: Today['lists']['later'] = [];
  for (const unit of units) {
    const inColumn = items.filter((item) => columnOf(item) === unit.id);
    for (const horizon of HORIZONS) {
      const inCell = inColumn.filter((item) => item.horizon === horizon);
      const first = inCell[0];
      if (first === undefined) continue;
      cells.push({
        unitId: unit.id,
        horizon,
        itemIds: inCell.map((item) => item.id),
        pressure: round2(1 - inCell.reduce((rest, item) => rest * (1 - item.pressure), 1)),
        kind: first.kind,
        working: inCell.some((item) => item.working),
      });
      if (horizon === 'week')
        week.push({ unitId: unit.id, itemIds: inCell.map((item) => item.id) });
      if (horizon === 'later') {
        later.push({
          unitId: unit.id,
          counts: KINDS.map((kind) => ({
            kind,
            count: inCell.filter((item) => item.kind === kind).length,
          })).filter((entry) => entry.count > 0),
        });
      }
    }
  }

  return {
    orbit: {
      itemIds: nowItems.slice(0, 5).map((item) => item.id),
      overflow: Math.max(0, nowItems.length - 5),
      nowCount: nowItems.length,
      urgentCount: items.filter((item) => item.attention === 'urgent' || item.attention === 'stop')
        .length,
      load: items.length,
      median: Math.max(1, ctx.median),
      working: items.some((item) => item.working),
    },
    field: { units, cells },
    lists: { now: nowItems.map((item) => item.id), week, later },
    context: {
      inExternalMeeting: ctx.inExternalMeeting,
      quietHoursActive: isWithinQuietHours(ctx.now, ctx.timeZone, ctx.settings.quietHours),
    },
  };
}

const HORIZON_LABELS: Record<Horizon, string> = { now: 'Now', week: 'This week', later: 'Later' };
const SEVERITY_LABELS = {
  P0: 'P0 critical',
  P1: 'P1 high',
  P2: 'P2 medium',
  P3: 'P3 low',
} as const;

export function buildViews(allItems: readonly Item[], agentCount: number): Views {
  const open = allItems.filter((item) => !isToConfirm(item));
  const proposals = allItems.filter((item) => item.kind === 'proposal');
  const commitments = allItems.filter(
    (item) => item.kind === 'commitment_by' || item.kind === 'commitment_to',
  );
  const tasks = allItems.filter((item) => item.kind === 'task');
  const alerts = allItems.filter((item) => item.kind === 'alert');

  const byClass = new Map<string, { label: string; items: Item[] }>();
  for (const item of [...proposals].sort((a, b) => expiryTime(a) - expiryTime(b))) {
    if (item.detail.kind !== 'proposal') continue;
    const group = byClass.get(item.detail.actionClass) ?? {
      label: item.detail.actionClassLabel,
      items: [],
    };
    group.items.push(item);
    byClass.set(item.detail.actionClass, group);
  }

  const byDue = (a: Item, b: Item): number => dueTime(a) - dueTime(b) || byPressure(a, b);
  const confirmed = commitments.filter((item) => !isToConfirm(item));

  const taskSections: Views['tasks'] = [];
  for (const horizon of HORIZONS) {
    const inHorizon = tasks.filter((item) => item.horizon === horizon).sort(byPressure);
    if (inHorizon.length === 0) continue;
    const byUnit = new Map<string, { name: string; items: Item[]; total: number }>();
    for (const item of inHorizon) {
      const group = byUnit.get(item.unit.id) ?? { name: item.unit.name, items: [], total: 0 };
      group.items.push(item);
      group.total += item.pressure;
      byUnit.set(item.unit.id, group);
    }
    const groups = [...byUnit.entries()].sort(([idA, a], [idB, b]) => {
      if (idA === OTHER_UNIT.id) return 1;
      if (idB === OTHER_UNIT.id) return -1;
      return b.total - a.total || a.name.localeCompare(b.name);
    });
    taskSections.push({
      horizon,
      label: HORIZON_LABELS[horizon],
      groups: groups.map(([id, group]) => ({
        id,
        label: group.name,
        itemIds: group.items.map((item) => item.id),
      })),
    });
  }

  const alertGroups: Views['alerts'] = [];
  for (const severity of ['P0', 'P1', 'P2', 'P3'] as const) {
    const inSeverity = alerts.filter((item) => item.severity === severity).sort(byPressure);
    if (inSeverity.length === 0) continue;
    alertGroups.push({
      id: severity,
      label: SEVERITY_LABELS[severity],
      itemIds: inSeverity.map((item) => item.id),
    });
  }

  return {
    counts: {
      today: open.length,
      proposals: proposals.length,
      commitments: commitments.length,
      tasks: tasks.length,
      alerts: alerts.length,
      agents: agentCount,
    },
    proposals: [...byClass.entries()].map(([id, group]) => ({
      id,
      label: group.label,
      itemIds: group.items.map((item) => item.id),
    })),
    commitments: {
      owedByMe: confirmed
        .filter((item) => item.kind === 'commitment_by')
        .sort(byDue)
        .map((i) => i.id),
      owedToMe: confirmed
        .filter((item) => item.kind === 'commitment_to')
        .sort(byDue)
        .map((i) => i.id),
      toConfirm: commitments
        .filter(isToConfirm)
        .sort(byPressure)
        .map((item) => item.id),
    },
    tasks: taskSections,
    alerts: alertGroups,
  };
}
