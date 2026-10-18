import { afterAll, describe, expect, it } from 'vitest';
import { SCENARIOS, type Item, type Scenario, type Snapshot } from '../domain/types.js';
import { expectContract, openStream, startHarness, validator, type Harness } from './harness.js';
import { snapshotInvariants } from './invariants.js';

const ONLINE = SCENARIOS.filter((scenario) => scenario !== 'offline');
const covered = new Set<string>();

function mark(operationId: string): void {
  covered.add(operationId);
}

async function exerciseEveryEndpoint(harness: Harness, scenario: Scenario): Promise<void> {
  const { call } = harness;
  // stale-client answers 426 to a versioned request; the others accept the app's version.
  const versioned = scenario === 'stale-client' ? {} : { 'desktop-client-version': '0.1.0' };

  const me = await call('GET', '/desktop/v1/me', { headers: versioned });
  expectContract('GET', '/me', me, 200);
  mark('getMe');

  const snapshotReply = await call('GET', '/desktop/v1/snapshot');
  expectContract('GET', '/snapshot', snapshotReply, 200);
  mark('getSnapshot');
  const snapshot = snapshotReply.body as Snapshot;
  expect(snapshotInvariants(snapshot)).toEqual([]);

  const today = await call('GET', '/desktop/v1/today');
  expectContract('GET', '/today', today, 200);
  mark('getToday');
  expect(today.body).toEqual(snapshot.today);

  const list = await call('GET', '/desktop/v1/items');
  expectContract('GET', '/items', list, 200);
  mark('listItems');
  const open = snapshot.items.filter(
    (item) =>
      !(
        (item.detail.kind === 'commitment_by' || item.detail.kind === 'commitment_to') &&
        item.detail.toConfirm
      ),
  );
  const firstPage = list.body as { items: Item[]; nextCursor: string | null };
  expect(firstPage.items.length + (firstPage.nextCursor === null ? 0 : 1)).toBeGreaterThan(0);

  const paged: Item[] = [];
  let cursor: string | null = null;
  do {
    const page = await call(
      'GET',
      `/desktop/v1/items?limit=5${cursor === null ? '' : `&cursor=${cursor}`}`,
    );
    expectContract('GET', '/items', page, 200);
    const body = page.body as { items: Item[]; nextCursor: string | null };
    paged.push(...body.items);
    cursor = body.nextCursor;
  } while (cursor !== null);
  expect(paged.map((item) => item.id).sort()).toEqual(open.map((item) => item.id).sort());

  const toConfirm = await call('GET', '/desktop/v1/items?state=to_confirm');
  expectContract('GET', '/items', toConfirm, 200);
  expect((toConfirm.body as { items: Item[] }).items.map((item) => item.id).sort()).toEqual(
    snapshot.views.commitments.toConfirm.slice().sort(),
  );

  const first = snapshot.items[0];
  if (!first) throw new Error(`${scenario} has no items`);
  const one = await call('GET', `/desktop/v1/items/${first.id}`);
  expectContract('GET', '/items/{itemId}', one, 200);
  mark('getItem');
  expect(one.body).toEqual(first);

  const agents = await call('GET', '/desktop/v1/agents');
  expectContract('GET', '/agents', agents, 200);
  mark('getAgents');
  // While the kill switch is on no agent is pausable, and pause and resume answer 403.
  const pausable = snapshot.agents.agents.find((agent) => agent.pausable);
  const agentId = pausable?.id ?? snapshot.agents.agents[0]?.id ?? 'none';
  const outcome = pausable ? 200 : 403;
  const paused = await call('POST', `/desktop/v1/agents/${agentId}/pause`);
  expectContract('POST', '/agents/{agentId}/pause', paused, outcome);
  mark('pauseAgent');
  const resumed = await call('POST', `/desktop/v1/agents/${agentId}/resume`);
  expectContract('POST', '/agents/{agentId}/resume', resumed, outcome);
  mark('resumeAgent');

  const settings = await call('GET', '/desktop/v1/settings');
  expectContract('GET', '/settings', settings, 200);
  mark('getSettings');
  const patched = await call('PATCH', '/desktop/v1/settings', { body: { pushBudgetPerHour: 5 } });
  expectContract('PATCH', '/settings', patched, 200);
  mark('updateSettings');

  const heartbeat = await call('POST', '/desktop/v1/sessions', {
    body: {
      deviceId: '5d1c1c0e-9b0e-4d57-8f43-0f9b1f0b7a10',
      clientVersion: '0.1.0',
      active: true,
      suppressed: false,
      idleSeconds: 0,
    },
  });
  expectContract('POST', '/sessions', heartbeat, 204);
  mark('recordSession');

  const stream = await openStream(harness, { lastEventId: snapshot.cursor });
  expect(stream.status).toBe(200);
  const response = await fetch(`${harness.origin}/desktop/v1/events`, {
    headers: { authorization: 'Bearer dev-test', 'last-event-id': snapshot.cursor },
  });
  expect(
    validator.validateResponse(
      'get',
      '/events',
      200,
      response.headers.get('content-type'),
      'stream',
    ).errors,
  ).toEqual([]);
  await response.body?.cancel();
  mark('streamEvents');

  const proposal = snapshot.items.find((item) => item.kind === 'proposal');
  if (!proposal) throw new Error(`${scenario} has no proposal`);
  const handoff = await call('POST', '/desktop/v1/handoff', {
    body: { itemId: proposal.id, instruction: 'Keep it short.' },
  });
  expectContract('POST', '/handoff', handoff, 202);
  mark('handOff');
  await harness.server.lance.idle();
  const afterHandoff = (await call('GET', '/desktop/v1/snapshot')).body as Snapshot;
  const current = afterHandoff.items.find((item) => item.id === proposal.id);
  const action = await call('POST', `/desktop/v1/items/${proposal.id}/actions/approve`, {
    body: { version: current?.version ?? 0 },
  });
  expectContract('POST', '/items/{itemId}/actions/{actionId}', action, 202);
  mark('runItemAction');
  await harness.server.lance.idle();

  // Drain everything the exercise caused; every event must be valid and ids must rise.
  const received = await stream.next(200, 400);
  expect(received.length).toBeGreaterThan(0);
  let lastId = Number(snapshot.cursor);
  for (const event of received) {
    expect(validator.validateSchema('StreamEvent', event.data).errors).toEqual([]);
    expect((event.data as { type: string }).type).toBe(event.event);
    if (event.id !== null) {
      expect(Number(event.id)).toBeGreaterThan(lastId);
      lastId = Number(event.id);
    }
  }
  stream.close();

  const after = await call('GET', '/desktop/v1/snapshot');
  expectContract('GET', '/snapshot', after, 200);
  expect(snapshotInvariants(after.body as Snapshot)).toEqual([]);
}

describe.each(ONLINE)('scenario %s', (scenario) => {
  it('answers every endpoint as the contract says and keeps its invariants', async () => {
    const harness = await startHarness({ scenario });
    try {
      await exerciseEveryEndpoint(harness, scenario);
    } finally {
      await harness.close();
    }
  });
});

describe('scenario shapes', () => {
  it.each([
    ['quiet', 3],
    ['normal', 18],
    ['overloaded', 42],
  ] as const)('%s holds the open count the spec names', async (scenario, load) => {
    const harness = await startHarness({ scenario });
    try {
      const snapshot = (await harness.call('GET', '/desktop/v1/snapshot')).body as Snapshot;
      expect(snapshot.today.orbit.load).toBe(load);
    } finally {
      await harness.close();
    }
  });

  it('normal has exactly one urgent item', async () => {
    const harness = await startHarness({ scenario: 'normal' });
    try {
      const snapshot = (await harness.call('GET', '/desktop/v1/snapshot')).body as Snapshot;
      expect(snapshot.today.orbit.urgentCount).toBe(1);
    } finally {
      await harness.close();
    }
  });

  it('overloaded sits above its median', async () => {
    const harness = await startHarness({ scenario: 'overloaded' });
    try {
      const { orbit } = (await harness.call('GET', '/desktop/v1/today')).body as Snapshot['today'];
      expect(orbit.load).toBeGreaterThan(orbit.median);
    } finally {
      await harness.close();
    }
  });

  it('incident holds a P0 alert first and the kill switch on', async () => {
    const harness = await startHarness({ scenario: 'incident' });
    try {
      const snapshot = (await harness.call('GET', '/desktop/v1/snapshot')).body as Snapshot;
      expect(snapshot.settings.global.paused).toBe(true);
      expect(snapshot.views.alerts[0]?.id).toBe('P0');
      const p0 = snapshot.items.find((item) => item.severity === 'P0');
      expect(p0?.attention).toBe('stop');
    } finally {
      await harness.close();
    }
  });

  it('external-meeting sets the meeting context', async () => {
    const harness = await startHarness({ scenario: 'external-meeting' });
    try {
      const today = (await harness.call('GET', '/desktop/v1/today')).body as Snapshot['today'];
      expect(today.context.inExternalMeeting).toBe(true);
    } finally {
      await harness.close();
    }
  });

  it('stale-client answers 426 to a versioned request and offers the minimum', async () => {
    const harness = await startHarness({ scenario: 'stale-client' });
    try {
      const reply = await harness.call('GET', '/desktop/v1/me', {
        headers: { 'desktop-client-version': '0.1.0' },
      });
      expectContract('GET', '/me', reply, 426);
      expect((reply.body as { minClientVersion: string }).minClientVersion).toBe('99.0.0');
      const unversioned = await harness.call('GET', '/desktop/v1/me');
      expectContract('GET', '/me', unversioned, 200);
    } finally {
      await harness.close();
    }
  });
});

describe('scenario offline', () => {
  it('refuses every /desktop/v1 request at the connection and keeps /__mock working', async () => {
    const harness = await startHarness({ scenario: 'offline' });
    try {
      for (const path of ['/desktop/v1/me', '/desktop/v1/snapshot', '/desktop/v1/events']) {
        await expect(
          fetch(`${harness.origin}${path}`, { headers: { authorization: 'Bearer dev-test' } }),
        ).rejects.toThrow();
      }
      const state = await harness.call('GET', '/__mock/state', { auth: false });
      expect(state.status).toBe(200);
      const switched = await harness.call('POST', '/__mock/scenario', {
        auth: false,
        body: { scenario: 'normal' },
      });
      expect(switched.status).toBe(200);
      expectContract('GET', '/me', await harness.call('GET', '/desktop/v1/me'), 200);
    } finally {
      await harness.close();
    }
  });

  it('drops an open stream when the scenario becomes offline', async () => {
    const harness = await startHarness();
    try {
      const stream = await openStream(harness);
      expect(stream.status).toBe(200);
      expect(harness.server.openStreamCount()).toBe(1);
      await harness.call('POST', '/__mock/scenario', {
        auth: false,
        body: { scenario: 'offline' },
      });
      expect(harness.server.openStreamCount()).toBe(0);
      stream.close();
    } finally {
      await harness.close();
    }
  });
});

afterAll(() => {
  const defined = validator
    .operations()
    .map((operation) => operation.operationId)
    .sort();
  expect([...covered].sort()).toEqual(defined);
});
