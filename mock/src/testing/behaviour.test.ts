import { afterEach, describe, expect, it } from 'vitest';
import { MockClock } from '../domain/clock.js';
import { EventLog } from '../domain/events.js';
import type { Item, Snapshot } from '../domain/types.js';
import { parseCommand } from '../cliCommand.js';
import {
  expectContract,
  openStream,
  startHarness,
  type Harness,
  type StreamedEvent,
} from './harness.js';
import { snapshotInvariants } from './invariants.js';

let harness: Harness | undefined;
afterEach(async () => {
  await harness?.close();
  harness = undefined;
});

async function started(options: Parameters<typeof startHarness>[0] = {}): Promise<Harness> {
  harness = await startHarness(options);
  return harness;
}

const snapshotOf = async (h: Harness): Promise<Snapshot> =>
  (await h.call('GET', '/desktop/v1/snapshot')).body as Snapshot;

const find = (snapshot: Snapshot, predicate: (item: Item) => boolean): Item => {
  const item = snapshot.items.find(predicate);
  if (!item) throw new Error('the scenario has no such item');
  return item;
};

const act = (h: Harness, item: Item, actionId: string, extra: Record<string, unknown> = {}) =>
  h.call('POST', `/desktop/v1/items/${item.id}/actions/${actionId}`, {
    body: { version: item.version, ...extra },
  });

describe('an action in flight', () => {
  it('answers 409 with the current item to a second action sent before the first settles', async () => {
    const h = await started({ actionDelayMs: 60 });
    const stream = await openStream(h);
    const item = find(
      await snapshotOf(h),
      (i) => i.kind === 'commitment_by' && i.actions.some((a) => a.id === 'dismiss'),
    );
    const first = await act(h, item, 'settle');
    expectContract('POST', '/items/{itemId}/actions/{actionId}', first, 200);
    const second = await act(h, item, 'dismiss');
    expectContract('POST', '/items/{itemId}/actions/{actionId}', second, 409);
    expect((second.body as { item: Item }).item.id).toBe(item.id);

    const events = await stream.next(10, 400);
    stream.close();
    const removals = events.filter((event) => event.event === 'item.removed');
    expect(removals).toHaveLength(1);
    expect((removals[0]?.data as { correlationId: string }).correlationId).toBe(
      (first.body as { correlationId: string }).correlationId,
    );
  });

  it('accepts a new action once the first has settled', async () => {
    const h = await started({ actionDelayMs: 0 });
    const item = find(await snapshotOf(h), (i) => i.kind === 'commitment_by');
    const snooze = await act(h, item, 'snooze', { until: '2026-10-30T09:00:00.000Z' });
    expect(snooze.status).toBe(200);
    await h.server.lance.idle();
    const current = (await h.call('GET', `/desktop/v1/items/${item.id}`)).body as Item;
    expect((await act(h, current, 'settle')).status).toBe(200);
  });

  it('does nothing for a step still pending when a scenario loads, and frees the item', async () => {
    const h = await started({ actionDelayMs: 60 });
    const stream = await openStream(h);
    const item = find(await snapshotOf(h), (i) => i.kind === 'commitment_by');
    expect((await act(h, item, 'settle')).status).toBe(200);
    await h.call('POST', '/__mock/scenario', { auth: false, body: { scenario: 'normal' } });
    await h.server.lance.idle();
    const events = await stream.next(20, 300);
    stream.close();
    expect(events.map((event) => event.event)).not.toContain('item.removed');
    const after = await snapshotOf(h);
    const still = find(after, (i) => i.id === item.id);
    expect((await act(h, still, 'snooze', { until: '2026-10-30T09:00:00.000Z' })).status).toBe(200);
  });

  it('offers no actions on the working copy of a proposal being approved', async () => {
    const h = await started();
    const stream = await openStream(h);
    const item = find(await snapshotOf(h), (i) => i.kind === 'proposal');
    expect((await act(h, item, 'approve')).status).toBe(202);
    const events: StreamedEvent[] = await stream.next(2, 1000);
    stream.close();
    const working = (events[0]?.data as { item: Item }).item;
    expect(working.working).toBe(true);
    expect(working.actions).toEqual([]);
  });
});

describe('event ids', () => {
  it('start above an earlier process, so its Last-Event-ID answers 410', () => {
    const clock = new MockClock(new Date('2026-10-16T09:00:00.000Z'));
    const earlier = new EventLog(clock, 5000);
    const later = new EventLog(clock, 9000);
    expect(earlier.replayAfter(5000)).toEqual([]);
    expect(later.replayAfter(5000)).toBeNull();
    expect(later.replayAfter(9000)).toEqual([]);
  });

  it('start at the wall clock by default and rise by one', () => {
    const before = Date.now();
    const log = new EventLog(new MockClock(new Date()));
    const start = log.latestId();
    expect(start).toBeGreaterThanOrEqual(before);
    const event = { type: 'client.deprecated', minClientVersion: '0.1.0', message: null } as const;
    expect(log.append(event)).toBe(start + 1);
    expect(log.append(event)).toBe(start + 2);
  });
});

describe('hand-off capability', () => {
  it('is offered by default and withdrawn by POST /__mock/capabilities', async () => {
    const h = await started();
    expect(
      ((await h.call('GET', '/desktop/v1/me')).body as { capabilities: { handoff: boolean } })
        .capabilities.handoff,
    ).toBe(true);
    const item = find(await snapshotOf(h), (i) => i.kind === 'task');

    await h.call('POST', '/__mock/capabilities', { auth: false, body: { handoff: false } });
    const me = await h.call('GET', '/desktop/v1/me');
    expectContract('GET', '/me', me, 200);
    expect((me.body as { capabilities: { handoff: boolean } }).capabilities.handoff).toBe(false);
    const refused = await h.call('POST', '/desktop/v1/handoff', { body: { itemId: item.id } });
    expectContract('POST', '/handoff', refused, 404);

    await h.call('POST', '/__mock/capabilities', { auth: false, body: { handoff: true } });
    expectContract(
      'POST',
      '/handoff',
      await h.call('POST', '/desktop/v1/handoff', { body: { itemId: item.id } }),
      202,
    );
  });

  it('refuses a capabilities request that is not a boolean', async () => {
    const h = await started();
    const reply = await h.call('POST', '/__mock/capabilities', {
      auth: false,
      body: { handoff: 'yes' },
    });
    expect(reply.status).toBe(400);
  });

  it('has a CLI command', () => {
    expect(parseCommand(['capabilities', 'handoff', 'off']).body).toEqual({ handoff: false });
    expect(() => parseCommand(['capabilities', 'handoff', 'maybe'])).toThrow();
  });
});

describe('item versions', () => {
  it('continue from the highest version so far when an id returns after a scenario switch', async () => {
    const h = await started();
    const before = find(await snapshotOf(h), (i) => i.kind === 'proposal');
    await h.call('POST', '/__mock/scenario', { auth: false, body: { scenario: 'quiet' } });
    expect((await snapshotOf(h)).items.some((i) => i.id === before.id)).toBe(false);
    await h.call('POST', '/__mock/scenario', { auth: false, body: { scenario: 'normal' } });
    const back = find(await snapshotOf(h), (i) => i.id === before.id);
    expect(back.version).toBeGreaterThan(before.version);
  });
});

describe('the kill switch', () => {
  it('leaves no agent pausable and answers 403 to pause and resume', async () => {
    const h = await started({ scenario: 'incident' });
    const { agents } = (await snapshotOf(h)).agents;
    expect(agents.every((agent) => !agent.pausable)).toBe(true);
    const id = agents[0]?.id ?? '';
    expectContract(
      'POST',
      '/agents/{agentId}/pause',
      await h.call('POST', `/desktop/v1/agents/${id}/pause`),
      403,
    );
    expectContract(
      'POST',
      '/agents/{agentId}/resume',
      await h.call('POST', `/desktop/v1/agents/${id}/resume`),
      403,
    );
  });
});

describe('a snoozed alert', () => {
  it('is raised again, with a higher version, when the clock passes its until', async () => {
    const h = await started();
    const alert = find(await snapshotOf(h), (i) => i.kind === 'alert');
    expect((await act(h, alert, 'snooze', { until: '2026-10-16T11:00:00.000Z' })).status).toBe(200);
    await h.server.lance.idle();
    expect((await snapshotOf(h)).items.some((i) => i.id === alert.id)).toBe(false);

    await h.call('POST', '/__mock/clock', { auth: false, body: { advanceSeconds: 60 * 60 } });
    expect((await snapshotOf(h)).items.some((i) => i.id === alert.id)).toBe(false);

    const stream = await openStream(h);
    await h.call('POST', '/__mock/clock', { auth: false, body: { advanceSeconds: 90 * 60 } });
    const events = await stream.next(20, 300);
    stream.close();
    const raised = events.find((event) => event.event === 'alert.raised');
    expect((raised?.data as { item: Item }).item.id).toBe(alert.id);
    expect((raised?.data as { item: Item }).item.version).toBeGreaterThan(alert.version);
    expect((await snapshotOf(h)).items.some((i) => i.id === alert.id)).toBe(true);
  });
});

describe('GET /items filters', () => {
  it('returns only the kind asked for', async () => {
    const h = await started();
    const reply = await h.call('GET', '/desktop/v1/items?kind=task&limit=200');
    expectContract('GET', '/items', reply, 200);
    const { items } = reply.body as { items: Item[] };
    expect(items.length).toBeGreaterThan(0);
    expect(items.every((item) => item.kind === 'task')).toBe(true);
  });

  it('returns only the horizon asked for, and combines the filters', async () => {
    const h = await started();
    const week = (await h.call('GET', '/desktop/v1/items?horizon=week&limit=200')).body as {
      items: Item[];
    };
    expect(week.items.length).toBeGreaterThan(0);
    expect(week.items.every((item) => item.horizon === 'week')).toBe(true);
    const both = (await h.call('GET', '/desktop/v1/items?horizon=now&kind=proposal&limit=200'))
      .body as { items: Item[] };
    expect(both.items.length).toBeGreaterThan(0);
    expect(both.items.every((item) => item.horizon === 'now' && item.kind === 'proposal')).toBe(
      true,
    );
  });
});

describe('aggregate events', () => {
  it('carry a Today and views that satisfy the invariants and match the snapshot', async () => {
    const h = await started();
    const stream = await openStream(h);
    await h.call('POST', '/__mock/emit', {
      auth: false,
      body: { recipe: 'alert', severity: 'P1' },
    });
    const events = await stream.next(3);
    stream.close();
    const today = events.find((event) => event.event === 'today.updated');
    const views = events.find((event) => event.event === 'views.updated');
    const snapshot = await snapshotOf(h);
    const todayPayload = (today?.data as { today: Snapshot['today'] }).today;
    const viewsPayload = (views?.data as { views: Snapshot['views'] }).views;
    expect(todayPayload).toEqual(snapshot.today);
    expect(viewsPayload).toEqual(snapshot.views);
    expect(snapshotInvariants({ ...snapshot, today: todayPayload, views: viewsPayload })).toEqual(
      [],
    );
  });
});
