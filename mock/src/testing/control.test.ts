import { afterEach, describe, expect, it } from 'vitest';
import type { Item, Snapshot, Today } from '../domain/types.js';
import { openStream, startHarness, START, type Harness } from './harness.js';

let harness: Harness | undefined;
afterEach(async () => {
  await harness?.close();
  harness = undefined;
});

async function started(options: Parameters<typeof startHarness>[0] = {}): Promise<Harness> {
  harness = await startHarness(options);
  return harness;
}

const post = (h: Harness, path: string, body: unknown) =>
  h.call('POST', path, { auth: false, body });
const snapshotOf = async (h: Harness): Promise<Snapshot> =>
  (await h.call('GET', '/desktop/v1/snapshot')).body as Snapshot;

describe('POST /__mock/emit', () => {
  it('raises an alert of the severity asked for, with its aggregates after it', async () => {
    const h = await started();
    const reply = await post(h, '/__mock/emit', {
      recipe: 'alert',
      severity: 'P0',
      title: 'Test alert',
    });
    const { itemId } = reply.body as { itemId: string };
    const item = (await h.call('GET', `/desktop/v1/items/${itemId}`)).body as Item;
    expect(item).toMatchObject({
      severity: 'P0',
      attention: 'stop',
      horizon: 'now',
      title: 'Test alert',
    });
    expect((await snapshotOf(h)).views.alerts[0]?.id).toBe('P0');
  });

  it('raises a proposal that expires when asked', async () => {
    const h = await started();
    const reply = await post(h, '/__mock/emit', { recipe: 'proposal', expiresInMinutes: 5 });
    const item = (
      await h.call('GET', `/desktop/v1/items/${(reply.body as { itemId: string }).itemId}`)
    ).body as Item;
    expect(item.attention).toBe('urgent');
    expect(item.detail).toMatchObject({ expiresAt: '2026-10-16T09:05:00.000Z' });
  });

  it('sends a contract event as given without changing state', async () => {
    const h = await started();
    const before = await snapshotOf(h);
    const stream = await openStream(h);
    await post(h, '/__mock/emit', {
      event: { type: 'client.deprecated', minClientVersion: '3.0.0', message: null },
    });
    const [event] = await stream.next(1);
    stream.close();
    expect(event?.event).toBe('client.deprecated');
    const after = await snapshotOf(h);
    expect(after.items).toEqual(before.items);
    expect(Number(after.cursor)).toBe(Number(before.cursor) + 1);
  });

  it('refuses an event that is not in the contract', async () => {
    const h = await started();
    expect((await post(h, '/__mock/emit', { event: { type: 'item.removed' } })).status).toBe(400);
    expect((await post(h, '/__mock/emit', { recipe: 'alert', severity: 'P9' })).status).toBe(400);
    expect((await post(h, '/__mock/emit', {})).status).toBe(400);
  });
});

describe('POST /__mock/clock', () => {
  it('advances time, expires a proposal and re-rates the items time changes', async () => {
    const h = await started();
    const before = await snapshotOf(h);
    const expiring = before.items.find((i) => i.attention === 'urgent');
    expect(expiring?.kind).toBe('proposal');
    const stream = await openStream(h);
    const reply = await post(h, '/__mock/clock', { advanceSeconds: 20 * 60 });
    expect(reply.body).toMatchObject({ now: '2026-10-16T09:20:00.000Z' });
    const events = await stream.next(20, 500);
    stream.close();
    const removed = events.find((event) => event.event === 'item.removed');
    expect(removed?.data).toMatchObject({ itemId: expiring?.id });
    expect((removed?.data as { outcome: string }).outcome).toMatch(/^Expired/);
    const after = await snapshotOf(h);
    expect(after.items.some((i) => i.id === expiring?.id)).toBe(false);
    expect(after.today.orbit.urgentCount).toBe(0);
    const changed = after.items.filter((item) => {
      const was = before.items.find((i) => i.id === item.id);
      return was !== undefined && was.version !== item.version;
    });
    expect(changed.length).toBeGreaterThan(0);
  });

  it('sets time, and a day later turns due-today items into overdue ones in the now horizon', async () => {
    const h = await started();
    await post(h, '/__mock/clock', { set: '2026-10-17T20:00:00.000Z' });
    const snapshot = await snapshotOf(h);
    const overdue = snapshot.items.filter((i) => i.meta.includes('overdue'));
    expect(overdue.length).toBeGreaterThan(0);
    expect(overdue.every((i) => i.horizon === 'now')).toBe(true);
    expect(snapshot.serverTime).toBe('2026-10-17T20:00:00.000Z');
  });

  it('turns quiet hours on in the context when time reaches them, and says so on the stream', async () => {
    const h = await started();
    const stream = await openStream(h);
    await post(h, '/__mock/clock', { set: '2026-10-16T22:00:00.000Z' });
    const events = await stream.next(30, 500);
    stream.close();
    const today = events.filter((event) => event.event === 'today.updated').at(-1);
    expect((today?.data as { today: Today }).today.context.quietHoursActive).toBe(true);
    expect(
      ((await h.call('GET', '/desktop/v1/today')).body as Today).context.quietHoursActive,
    ).toBe(true);
  });

  it('starts at the configured instant and refuses nonsense', async () => {
    const h = await started();
    expect(
      ((await h.call('GET', '/desktop/v1/me')).body as { serverTime: string }).serverTime,
    ).toBe(START.toISOString());
    expect((await post(h, '/__mock/clock', { advanceSeconds: -5 })).status).toBe(400);
    expect((await post(h, '/__mock/clock', { set: 'yesterday' })).status).toBe(400);
  });
});

describe('POST /__mock/scenario and GET /__mock/state', () => {
  it('switches scenario and reports it', async () => {
    const h = await started();
    expect((await post(h, '/__mock/scenario', { scenario: 'quiet' })).status).toBe(200);
    expect((await snapshotOf(h)).today.orbit.load).toBe(3);
    expect((await h.call('GET', '/__mock/state', { auth: false })).body).toMatchObject({
      scenario: 'quiet',
    });
  });

  it('refuses a scenario it does not have', async () => {
    const h = await started();
    expect((await post(h, '/__mock/scenario', { scenario: 'chaos' })).status).toBe(400);
  });

  it('keeps event ids rising across a switch', async () => {
    const h = await started();
    const before = Number((await snapshotOf(h)).cursor);
    await post(h, '/__mock/scenario', { scenario: 'overloaded' });
    expect(Number((await snapshotOf(h)).cursor)).toBeGreaterThan(before);
  });
});

describe('sessions', () => {
  it('returns the heartbeats it received', async () => {
    const h = await started();
    const heartbeat = {
      deviceId: '5d1c1c0e-9b0e-4d57-8f43-0f9b1f0b7a10',
      clientVersion: '0.1.0',
      active: true,
      suppressed: false,
      idleSeconds: 12,
    };
    expect((await h.call('POST', '/desktop/v1/sessions', { body: heartbeat })).status).toBe(204);
    expect(
      (await h.call('POST', '/desktop/v1/sessions', { body: { ...heartbeat, active: false } }))
        .status,
    ).toBe(204);
    const { sessions } = (await h.call('GET', '/__mock/sessions', { auth: false })).body as {
      sessions: Record<string, unknown>[];
    };
    expect(sessions).toHaveLength(2);
    expect(sessions[0]).toMatchObject({ ...heartbeat, receivedAt: START.toISOString() });
    expect(sessions[1]).toMatchObject({ active: false });
  });

  it('answers 400 for a heartbeat that is not valid', async () => {
    const h = await started();
    expect((await h.call('POST', '/desktop/v1/sessions', { body: { deviceId: 'x' } })).status).toBe(
      400,
    );
  });
});
