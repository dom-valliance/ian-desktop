import { afterEach, describe, expect, it } from 'vitest';
import type { Snapshot } from '../domain/types.js';
import {
  AUTH,
  expectContract,
  openStream,
  startHarness,
  validator,
  type Harness,
} from './harness.js';

let harness: Harness | undefined;

afterEach(async () => {
  await harness?.close();
  harness = undefined;
});

async function started(options: Parameters<typeof startHarness>[0] = {}): Promise<Harness> {
  harness = await startHarness(options);
  return harness;
}

const cursorOf = async (h: Harness): Promise<number> =>
  Number(((await h.call('GET', '/desktop/v1/snapshot')).body as Snapshot).cursor);

const emitNote = (h: Harness, n: number): Promise<unknown> =>
  h.call('POST', '/__mock/emit', {
    auth: false,
    body: {
      event: { type: 'client.deprecated', minClientVersion: '0.1.0', message: `note ${String(n)}` },
    },
  });

describe('the event stream', () => {
  it('replays the five events missed while disconnected, in order', async () => {
    const h = await started();
    const cursor = await cursorOf(h);
    const first = await openStream(h, { lastEventId: String(cursor) });
    expect(first.status).toBe(200);
    first.close();

    for (const n of [1, 2, 3, 4, 5]) await emitNote(h, n);

    const second = await openStream(h, { lastEventId: String(cursor) });
    const events = await second.next(5);
    second.close();
    expect(events.map((event) => event.id)).toEqual([1, 2, 3, 4, 5].map((n) => String(cursor + n)));
    expect(events.map((event) => (event.data as { message: string }).message)).toEqual(
      [1, 2, 3, 4, 5].map((n) => `note ${String(n)}`),
    );
    expect(events.every((event) => event.event === 'client.deprecated')).toBe(true);
  });

  it('answers 410 for an id older than the 24 hour window', async () => {
    const h = await started();
    const cursor = await cursorOf(h);
    await emitNote(h, 1);
    await h.call('POST', '/__mock/clock', { auth: false, body: { advanceSeconds: 25 * 3600 } });
    const reply = await h.call('GET', '/desktop/v1/events', {
      headers: { 'last-event-id': String(cursor) },
    });
    expectContract('GET', '/events', reply, 410);
  });

  it('ages events out by their own time after the clock is set back', async () => {
    const h = await started();
    const start = (await h.call('GET', '/__mock/state', { auth: false })).body as { now: string };
    await emitNote(h, 1);
    await h.call('POST', '/__mock/clock', { auth: false, body: { advanceSeconds: 25 * 3600 } });
    await h.call('POST', '/__mock/clock', { auth: false, body: { set: start.now } });
    const cursor = await cursorOf(h);
    await emitNote(h, 2);
    await h.call('POST', '/__mock/clock', { auth: false, body: { advanceSeconds: 25 * 3600 } });
    const reply = await h.call('GET', '/desktop/v1/events', {
      headers: { 'last-event-id': String(cursor) },
    });
    expectContract('GET', '/events', reply, 410);
  });

  it('keeps an id that is the newest to have aged out, and replays what follows in order', async () => {
    const h = await started();
    const cursor = await cursorOf(h);
    await emitNote(h, 1);
    await h.call('POST', '/__mock/clock', { auth: false, body: { advanceSeconds: 25 * 3600 } });
    const stream = await openStream(h, { lastEventId: String(cursor + 1) });
    expect(stream.status).toBe(200);
    const replayed = await stream.next(50, 500);
    stream.close();
    // Advancing a day expires proposals, so there is something to replay, and none of it is
    // the event the client already holds.
    expect(replayed.length).toBeGreaterThan(0);
    const ids = replayed.map((event) => Number(event.id));
    expect(ids.every((id) => id > cursor + 1)).toBe(true);
    expect(ids).toEqual([...ids].sort((a, b) => a - b));
    expect(replayed.map((event) => event.event)).toContain('item.removed');
  });

  it('answers 410 for an id newer than the latest event', async () => {
    const h = await started();
    const cursor = await cursorOf(h);
    const reply = await h.call('GET', '/desktop/v1/events', {
      headers: { 'last-event-id': String(cursor + 1) },
    });
    expectContract('GET', '/events', reply, 410);
  });

  it('answers 410 for a Last-Event-ID that is not a number', async () => {
    const h = await started();
    const reply = await h.call('GET', '/desktop/v1/events', {
      headers: { 'last-event-id': 'abc' },
    });
    expectContract('GET', '/events', reply, 410);
  });

  it('accepts the latest id and sends nothing until something happens', async () => {
    const h = await started();
    const stream = await openStream(h, { lastEventId: String(await cursorOf(h)) });
    expect(stream.status).toBe(200);
    expect(await stream.next(1, 200)).toEqual([]);
    await emitNote(h, 1);
    expect(await stream.next(1)).toHaveLength(1);
    stream.close();
  });

  it('numbers events strictly upward and puts item events before the aggregates they change', async () => {
    const h = await started();
    const stream = await openStream(h);
    await h.call('POST', '/__mock/emit', {
      auth: false,
      body: { recipe: 'alert', severity: 'P1' },
    });
    const events = await stream.next(3);
    stream.close();
    expect(events.map((event) => event.event)).toEqual([
      'alert.raised',
      'today.updated',
      'views.updated',
    ]);
    const ids = events.map((event) => Number(event.id));
    expect(ids[1]).toBe((ids[0] ?? 0) + 1);
    expect(ids[2]).toBe((ids[1] ?? 0) + 1);
    for (const event of events) {
      expect(validator.validateSchema('StreamEvent', event.data).errors).toEqual([]);
      expect((event.data as { type: string }).type).toBe(event.event);
    }
  });

  it('sends a heartbeat with no id on the configured interval and never replays it', async () => {
    const h = await started({ heartbeatIntervalMs: 40 });
    const cursor = await cursorOf(h);
    const stream = await openStream(h);
    const beats = await stream.next(2);
    stream.close();
    expect(beats.every((beat) => beat.event === 'heartbeat' && beat.id === null)).toBe(true);
    expect(validator.validateSchema('StreamEvent', beats[0]?.data).errors).toEqual([]);

    expect((await h.call('GET', '/__mock/state', { auth: false })).body).toMatchObject({
      latestEventId: cursor,
    });
    const reconnect = await openStream(h, { lastEventId: String(cursor) });
    const next = await reconnect.next(1);
    reconnect.close();
    expect(next[0]?.id).toBeNull();
  });

  it('does not store a raw heartbeat', async () => {
    const h = await started();
    const cursor = await cursorOf(h);
    const stream = await openStream(h);
    await h.call('POST', '/__mock/emit', {
      auth: false,
      body: { event: { type: 'heartbeat', serverTime: '2026-10-16T09:00:00.000Z' } },
    });
    const [beat] = await stream.next(1);
    stream.close();
    expect(beat?.id).toBeNull();
    expect(await cursorOf(h)).toBe(cursor);
  });

  it('tells a live stream what a scenario switch changed', async () => {
    const h = await started();
    const stream = await openStream(h);
    await h.call('POST', '/__mock/scenario', { auth: false, body: { scenario: 'incident' } });
    const events = await stream.next(40, 1000);
    stream.close();
    const types = events.map((event) => event.event);
    expect(types).toContain('alert.raised');
    expect(types).toContain('settings.updated');
    expect(types).toContain('agent.updated');
    expect(types.lastIndexOf('item.upserted')).toBeLessThan(types.indexOf('today.updated'));
    expect(types.at(-1)).toBe('views.updated');
  });

  it('sends client.deprecated when the scenario raises the minimum version', async () => {
    const h = await started();
    const stream = await openStream(h);
    await h.call('POST', '/__mock/scenario', { auth: false, body: { scenario: 'stale-client' } });
    const events = await stream.next(5, 1000);
    stream.close();
    const deprecated = events.find((event) => event.event === 'client.deprecated');
    expect(deprecated?.data).toMatchObject({ minClientVersion: '99.0.0' });
  });

  it('sends bytes and nosniff before any event or heartbeat', async () => {
    const h = await started({ heartbeatIntervalMs: 60_000 });
    const response = await fetch(`${h.origin}/desktop/v1/events`, { headers: AUTH });
    expect(response.headers.get('x-content-type-options')).toBe('nosniff');
    const reader = response.body?.getReader();
    const first = (await reader?.read()) as { value: Uint8Array } | undefined;
    expect(new TextDecoder().decode(first?.value)).toBe(': open\n\n');
    await reader?.cancel();
  });

  it('refuses a stream without a bearer token', async () => {
    const h = await started();
    const reply = await h.call('GET', '/desktop/v1/events', { auth: false });
    expectContract('GET', '/events', reply, 401);
  });
});
