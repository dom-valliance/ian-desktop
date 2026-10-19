import { afterEach, describe, expect, it } from 'vitest';
import type { Item, Snapshot } from '../domain/types.js';
import {
  expectContract,
  openStream,
  startHarness,
  validator,
  type EventStream,
  type Harness,
  type StreamedEvent,
} from './harness.js';

let harness: Harness | undefined;
afterEach(async () => {
  await harness?.close();
  harness = undefined;
});

async function started(scenario: Parameters<typeof startHarness>[0] = {}): Promise<Harness> {
  harness = await startHarness(scenario);
  return harness;
}

const snapshotOf = async (h: Harness): Promise<Snapshot> =>
  (await h.call('GET', '/desktop/v1/snapshot')).body as Snapshot;

const find = (snapshot: Snapshot, predicate: (item: Item) => boolean): Item => {
  const item = snapshot.items.find(predicate);
  if (!item) throw new Error('the scenario has no such item');
  return item;
};

async function act(
  h: Harness,
  item: Item,
  actionId: string,
  extra: Record<string, unknown> = {},
  expectedStatus = 200,
): Promise<string> {
  const path = `/desktop/v1/items/${item.id}/actions/${actionId}`;
  const reply = await h.call('POST', path, { body: { version: item.version, ...extra } });
  expectContract('POST', '/items/{itemId}/actions/{actionId}', reply, expectedStatus);
  return (reply.body as { correlationId: string }).correlationId;
}

/** Reads events until the closing `views.updated` of the operation has arrived. */
async function untilViews(stream: EventStream, limit = 12): Promise<StreamedEvent[]> {
  const seen: StreamedEvent[] = [];
  while (seen.length < limit) {
    const [event] = await stream.next(1, 1500);
    if (!event) break;
    seen.push(event);
    if (event.event === 'views.updated') break;
  }
  return seen;
}

const correlationOf = (event: StreamedEvent): string | undefined =>
  (event.data as { correlationId?: string }).correlationId;

describe('actions that settle at once', () => {
  it('settles a commitment: 200, then item.removed with an outcome and its correlation id', async () => {
    const h = await started();
    const stream = await openStream(h);
    const item = find(
      await snapshotOf(h),
      (i) => i.kind === 'commitment_by' && i.actions.some((a) => a.id === 'settle'),
    );
    const correlationId = await act(h, item, 'settle');
    const events = await untilViews(stream);
    stream.close();
    expect(events.map((event) => event.event)).toEqual([
      'item.removed',
      'today.updated',
      'views.updated',
    ]);
    expect(events[0]?.data).toMatchObject({ itemId: item.id, correlationId });
    expect((events[0]?.data as { outcome: string }).outcome).toMatch(/^Settled/);
    expect((await h.call('GET', `/desktop/v1/items/${item.id}`)).status).toBe(404);
  });

  it('rejects a proposal: 200 and a removal that says nothing was sent', async () => {
    const h = await started();
    const stream = await openStream(h);
    const item = find(await snapshotOf(h), (i) => i.kind === 'proposal');
    const correlationId = await act(h, item, 'reject');
    const [removed] = await untilViews(stream);
    stream.close();
    expect(removed?.data).toMatchObject({ type: 'item.removed', correlationId });
  });

  it('dismisses a commitment awaiting confirmation', async () => {
    const h = await started();
    const item = find(
      await snapshotOf(h),
      (i) => i.detail.kind === 'commitment_to' && i.detail.toConfirm,
    );
    await act(h, item, 'dismiss');
    await h.server.lance.idle();
    expect((await snapshotOf(h)).items.some((i) => i.id === item.id)).toBe(false);
  });

  it('acknowledges an alert: 200 and alert.cleared with its correlation id', async () => {
    const h = await started();
    const stream = await openStream(h);
    const item = find(await snapshotOf(h), (i) => i.kind === 'alert');
    const correlationId = await act(h, item, 'acknowledge');
    const events = await untilViews(stream);
    stream.close();
    expect(events[0]?.data).toEqual({ type: 'alert.cleared', itemId: item.id, correlationId });
  });

  it('snoozes a commitment with the until it is sent and moves its due date', async () => {
    const h = await started();
    const stream = await openStream(h);
    const item = find(
      await snapshotOf(h),
      (i) => i.kind === 'commitment_by' && i.horizon === 'now',
    );
    const until = '2026-10-30T09:00:00.000Z';
    const correlationId = await act(h, item, 'snooze', { until });
    const events = await untilViews(stream);
    stream.close();
    const upserted = events[0]?.data as { item: Item; correlationId: string };
    expect(upserted.correlationId).toBe(correlationId);
    expect(upserted.item.dueAt).toBe(until);
    expect(upserted.item.horizon).toBe('later');
    expect(upserted.item.version).toBe(item.version + 1);
  });

  it('confirms a commitment into its tab', async () => {
    const h = await started();
    const before = await snapshotOf(h);
    const item = find(before, (i) => i.detail.kind === 'commitment_to' && i.detail.toConfirm);
    expect(before.views.commitments.toConfirm).toContain(item.id);
    const correlationId = await act(h, item, 'confirm');
    await h.server.lance.idle();
    const after = await snapshotOf(h);
    expect(after.views.commitments.toConfirm).not.toContain(item.id);
    expect(after.views.commitments.owedToMe).toContain(item.id);
    const confirmed = after.items.find((i) => i.id === item.id);
    expect(confirmed?.actions.map((a) => a.id)).toEqual(['settle', 'chase', 'snooze']);
    expect(correlationId).toMatch(/^corr_/);
  });
});

describe('actions that continue', () => {
  it('approves a proposal: 202, then working, then removal, all with one correlation id', async () => {
    const h = await started();
    const stream = await openStream(h);
    const item = find(await snapshotOf(h), (i) => i.kind === 'proposal');
    const correlationId = await act(h, item, 'approve', {}, 202);
    const events = await untilViews(stream);
    stream.close();
    const itemEvents = events.filter((event) => event.event.startsWith('item.'));
    expect(itemEvents.map((event) => event.event)).toEqual(['item.upserted', 'item.removed']);
    expect(itemEvents.map(correlationOf)).toEqual([correlationId, correlationId]);
    expect((itemEvents[0]?.data as { item: Item }).item.working).toBe(true);
    expect(events.at(-1)?.event).toBe('views.updated');
  });

  it('marks a task Done: 202, the task loses its Done action, a complete_task proposal follows', async () => {
    const h = await started();
    const stream = await openStream(h);
    const task = find(
      await snapshotOf(h),
      (i) => i.kind === 'task' && i.actions.some((a) => a.id === 'done'),
    );
    const correlationId = await act(h, task, 'done', {}, 202);
    const events = await untilViews(stream);
    const [taskEvent, proposalEvent] = events;
    expect(taskEvent?.data).toMatchObject({ type: 'item.upserted', correlationId });
    expect((taskEvent?.data as { item: Item }).item.actions).toEqual([]);
    const raised = proposalEvent?.data as { item: Item; correlationId: string };
    expect(raised.correlationId).toBe(correlationId);
    expect(raised.item.detail).toMatchObject({ kind: 'proposal', actionClass: 'complete_task' });

    const approved = await act(h, raised.item, 'approve', {}, 202);
    const finish: StreamedEvent[] = [];
    while (
      !finish.some(
        (event) =>
          event.event === 'item.removed' && (event.data as { itemId: string }).itemId === task.id,
      )
    ) {
      const batch = await untilViews(stream);
      if (batch.length === 0) break;
      finish.push(...batch);
    }
    stream.close();
    const removed = finish.filter((event) => event.event === 'item.removed');
    expect(removed.map((event) => (event.data as { itemId: string }).itemId)).toEqual([
      raised.item.id,
      task.id,
    ]);
    expect(removed.map(correlationOf)).toEqual([approved, approved]);
  });

  it('gives the task its Done action back when the complete_task proposal is rejected', async () => {
    const h = await started();
    const task = find(
      await snapshotOf(h),
      (i) => i.kind === 'task' && i.actions.some((a) => a.id === 'done'),
    );
    await act(h, task, 'done', {}, 202);
    await h.server.lance.idle();
    const proposal = find(
      await snapshotOf(h),
      (i) => i.detail.kind === 'proposal' && i.detail.actionClass === 'complete_task',
    );
    await act(h, proposal, 'reject');
    await h.server.lance.idle();
    const restored = find(await snapshotOf(h), (i) => i.id === task.id);
    expect(restored.actions.map((a) => a.id)).toEqual(['done']);
  });

  it('chases a commitment with a note: 202, the chase is requested and a proposal follows', async () => {
    const h = await started();
    const item = find(
      await snapshotOf(h),
      (i) => i.kind === 'commitment_to' && i.actions.some((a) => a.id === 'chase'),
    );
    const correlationId = await act(h, item, 'chase', { note: 'Asking again before Friday.' }, 202);
    await h.server.lance.idle();
    const after = await snapshotOf(h);
    const chased = find(after, (i) => i.id === item.id);
    expect(chased.detail).toMatchObject({ chase: { state: 'requested' } });
    expect(chased.actions.map((a) => a.id)).not.toContain('chase');
    const draft = find(after, (i) => i.detail.kind === 'proposal' && i.title.startsWith('Chase'));
    expect(draft.detail).toMatchObject({ summary: 'Asking again before Friday.' });
    expect(correlationId).toMatch(/^corr_/);
  });

  it('hands an item to Ian: 202 and events carrying the correlation id, ending in a proposal', async () => {
    const h = await started();
    const stream = await openStream(h);
    const item = find(await snapshotOf(h), (i) => i.kind === 'task');
    const reply = await h.call('POST', '/desktop/v1/handoff', {
      body: { itemId: item.id, instruction: 'Keep it short.' },
    });
    expectContract('POST', '/handoff', reply, 202);
    const { correlationId } = reply.body as { correlationId: string };
    const first = await untilViews(stream);
    const second = await untilViews(stream);
    stream.close();
    const withCorrelation = [...first, ...second].filter(
      (event) => correlationOf(event) === correlationId,
    );
    expect(withCorrelation.length).toBeGreaterThanOrEqual(3);
    const raised = withCorrelation.at(-1)?.data as { item: Item };
    expect(raised.item.detail).toMatchObject({ kind: 'proposal', summary: 'Keep it short.' });
  });
});

describe('refusals', () => {
  it('answers 409 with the current item when the version is stale', async () => {
    const h = await started();
    const item = find(await snapshotOf(h), (i) => i.kind === 'proposal');
    const reply = await h.call('POST', `/desktop/v1/items/${item.id}/actions/approve`, {
      body: { version: item.version + 5 },
    });
    expectContract('POST', '/items/{itemId}/actions/{actionId}', reply, 409);
    expect((reply.body as { item: Item }).item).toEqual(item);
  });

  it('answers 409 with the current item for an action the item does not offer', async () => {
    const h = await started();
    const item = find(await snapshotOf(h), (i) => i.kind === 'proposal');
    const reply = await h.call('POST', `/desktop/v1/items/${item.id}/actions/settle`, {
      body: { version: item.version },
    });
    expectContract('POST', '/items/{itemId}/actions/{actionId}', reply, 409);
  });

  it('answers 404 when an action arrives for an item that has already left', async () => {
    const h = await started();
    const item = find(await snapshotOf(h), (i) => i.kind === 'alert');
    await act(h, item, 'acknowledge');
    await h.server.lance.idle();
    const again = await h.call('POST', `/desktop/v1/items/${item.id}/actions/acknowledge`, {
      body: { version: item.version },
    });
    expectContract('POST', '/items/{itemId}/actions/{actionId}', again, 404);
  });

  it('answers 400 when an until action arrives without until', async () => {
    const h = await started();
    const item = find(await snapshotOf(h), (i) => i.kind === 'alert');
    const reply = await h.call('POST', `/desktop/v1/items/${item.id}/actions/snooze`, {
      body: { version: item.version },
    });
    expectContract('POST', '/items/{itemId}/actions/{actionId}', reply, 400);
  });

  it('answers 400 for a body that is not valid, and 404 for an unknown item', async () => {
    const h = await started();
    const bad = await h.call('POST', '/desktop/v1/items/prop_1/actions/approve', {
      body: { version: 'x' },
    });
    expectContract('POST', '/items/{itemId}/actions/{actionId}', bad, 400);
    const missing = await h.call('POST', '/desktop/v1/items/prop_nothing/actions/approve', {
      body: { version: 1 },
    });
    expectContract('POST', '/items/{itemId}/actions/{actionId}', missing, 404);
    expectContract('GET', '/items/{itemId}', await h.call('GET', '/desktop/v1/items/nothing'), 404);
    expectContract(
      'POST',
      '/handoff',
      await h.call('POST', '/desktop/v1/handoff', { body: { itemId: 'prop_nothing' } }),
      404,
    );
  });
});

describe('agents and settings', () => {
  it('pauses and resumes within scope and emits agent.updated', async () => {
    const h = await started();
    const stream = await openStream(h);
    const agent = (await snapshotOf(h)).agents.agents.find((a) => a.pausable);
    if (!agent) throw new Error('no pausable agent');
    const paused = await h.call('POST', `/desktop/v1/agents/${agent.id}/pause`);
    expect((paused.body as { state: string }).state).toBe('paused');
    const [event] = await stream.next(1);
    expect(event?.event).toBe('agent.updated');
    expect(validator.validateSchema('StreamEvent', event?.data).errors).toEqual([]);
    const resumed = await h.call('POST', `/desktop/v1/agents/${agent.id}/resume`);
    expect((resumed.body as { state: string }).state).toBe('idle');
    stream.close();
  });

  it('answers 403 when the agent is not pausable and 404 when it does not exist', async () => {
    const h = await started();
    const job = (await snapshotOf(h)).agents.agents.find((a) => !a.pausable);
    if (!job) throw new Error('no fixed agent');
    expectContract(
      'POST',
      '/agents/{agentId}/pause',
      await h.call('POST', `/desktop/v1/agents/${job.id}/pause`),
      403,
    );
    expectContract(
      'POST',
      '/agents/{agentId}/resume',
      await h.call('POST', `/desktop/v1/agents/${job.id}/resume`),
      403,
    );
    expectContract(
      'POST',
      '/agents/{agentId}/pause',
      await h.call('POST', '/desktop/v1/agents/nothing/pause'),
      404,
    );
  });

  it('refuses going live with 422 unless the principal is eligible', async () => {
    const h = await started({ scenario: 'normal' });
    const refused = await h.call('PATCH', '/desktop/v1/settings', { body: { mode: 'live' } });
    expectContract('PATCH', '/settings', refused, 422);
    expect((await h.call('GET', '/desktop/v1/settings')).body).toMatchObject({ mode: 'dry_run' });
  });

  it('allows going live when eligible, and emits settings.updated', async () => {
    const h = await started({ scenario: 'quiet' });
    const stream = await openStream(h);
    const reply = await h.call('PATCH', '/desktop/v1/settings', { body: { mode: 'live' } });
    expectContract('PATCH', '/settings', reply, 200);
    const [event] = await stream.next(1);
    stream.close();
    expect(event?.event).toBe('settings.updated');
    expect((event?.data as { settings: { mode: string } }).settings.mode).toBe('live');
    expect(((await h.call('GET', '/desktop/v1/me')).body as { mode: string }).mode).toBe('live');
  });

  it('answers a patch that changes nothing with the current settings and no event', async () => {
    const h = await started({ scenario: 'normal' });
    const stream = await openStream(h);
    const current = (await h.call('GET', '/desktop/v1/settings')).body as {
      pushBudgetPerHour: number;
    };
    const reply = await h.call('PATCH', '/desktop/v1/settings', {
      body: { pushBudgetPerHour: current.pushBudgetPerHour },
    });
    expectContract('PATCH', '/settings', reply, 200);
    expect(reply.body).toEqual(current);
    await h.call('POST', '/__mock/emit', { body: { recipe: 'alert', severity: 'P1' } });
    const [event] = await stream.next(1);
    stream.close();
    expect(event?.event).not.toBe('settings.updated');
  });

  it('answers 400 for an empty or invalid settings patch', async () => {
    const h = await started();
    expectContract(
      'PATCH',
      '/settings',
      await h.call('PATCH', '/desktop/v1/settings', { body: {} }),
      400,
    );
    expectContract(
      'PATCH',
      '/settings',
      await h.call('PATCH', '/desktop/v1/settings', { body: { pushBudgetPerHour: 99 } }),
      400,
    );
  });

  it('records the principal own pause and reflects it in /me', async () => {
    const h = await started();
    await h.call('PATCH', '/desktop/v1/settings', {
      body: { paused: true, pausedReason: 'Heads down.' },
    });
    expect((await h.call('GET', '/desktop/v1/settings')).body).toMatchObject({
      paused: true,
      pausedReason: 'Heads down.',
    });
    expect(((await h.call('GET', '/desktop/v1/me')).body as { status: string }).status).toBe(
      'paused',
    );
  });
});

describe('authentication and headers', () => {
  it.each([
    ['no header', undefined],
    ['a Basic header', 'Basic abc'],
    ['a bearer token that is not a dev token', 'Bearer abc'],
  ])('answers 401 with %s', async (_name, authorization) => {
    const h = await started();
    const reply = await h.call('GET', '/desktop/v1/me', {
      auth: false,
      ...(authorization === undefined ? {} : { headers: { authorization } }),
    });
    expectContract('GET', '/me', reply, 401);
  });

  it('accepts any dev token', async () => {
    const h = await started();
    const reply = await h.call('GET', '/desktop/v1/me', {
      auth: false,
      headers: { authorization: 'Bearer dev-anything-at-all' },
    });
    expectContract('GET', '/me', reply, 200);
  });

  it('does not version-check a malformed header, and answers 426 below the minimum', async () => {
    const h = await started({ scenario: 'stale-client' });
    const bad = await h.call('GET', '/desktop/v1/items', {
      headers: { 'desktop-client-version': 'new' },
    });
    expectContract('GET', '/items', bad, 200);
    const old = await h.call('GET', '/desktop/v1/items', {
      headers: { 'desktop-client-version': '98.9.9' },
    });
    expectContract('GET', '/items', old, 426);
    const current = await h.call('GET', '/desktop/v1/items', {
      headers: { 'desktop-client-version': '99.0.0' },
    });
    expectContract('GET', '/items', current, 200);
  });

  it('answers 400 for an unusable items query', async () => {
    const h = await started();
    expectContract('GET', '/items', await h.call('GET', '/desktop/v1/items?limit=0'), 400);
    expectContract('GET', '/items', await h.call('GET', '/desktop/v1/items?kind=bogus'), 400);
    expectContract('GET', '/items', await h.call('GET', '/desktop/v1/items?cursor=zzz'), 400);
  });
});
