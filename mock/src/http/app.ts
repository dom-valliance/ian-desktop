import Fastify, { type FastifyInstance, type FastifyReply, type FastifyRequest } from 'fastify';
import { MockClock } from '../domain/clock.js';
import { MockError } from '../domain/errors.js';
import type { StoredEvent } from '../domain/events.js';
import { MockLance } from '../domain/lance.js';
import type { Scenario } from '../domain/types.js';
import {
  zEventId,
  zGetItemPath,
  zHandOffBody,
  zListItemsQuery,
  zPauseAgentPath,
  zRecordSessionBody,
  zRunItemActionBody,
  zRunItemActionPath,
  zUpdateSettingsBody,
  zVersion,
} from '../generated/zod.gen.js';
import { defaultStart } from '../config.js';
import {
  parseWith,
  zCapabilitiesRequest,
  zClockRequest,
  zEmitRequest,
  zScenarioRequest,
} from './mockApi.js';
import { sendProblem } from './problem.js';

export interface MockOptions {
  startAt?: Date;
  scenario?: Scenario;
  heartbeatIntervalMs?: number;
  actionDelayMs?: number;
  logLevel?: string;
}

export interface MockServer {
  app: FastifyInstance;
  lance: MockLance;
  /** Ends every open event stream, as a dropped connection would. */
  dropStreams(): void;
  openStreamCount(): number;
}

const BEARER = /^Bearer dev-\S+$/;

function compareVersions(a: string, b: string): number {
  const left = a.split('.').map(Number);
  const right = b.split('.').map(Number);
  for (let i = 0; i < 3; i += 1) {
    const difference = (left[i] ?? 0) - (right[i] ?? 0);
    if (difference !== 0) return difference;
  }
  return 0;
}

function clientErrorStatus(error: unknown): number | undefined {
  if (typeof error !== 'object' || error === null || !('statusCode' in error)) return undefined;
  const { statusCode } = error;
  return typeof statusCode === 'number' && statusCode >= 400 && statusCode < 500
    ? statusCode
    : undefined;
}

function formatEvent(stored: StoredEvent): string {
  const id = stored.id === null ? '' : `id: ${stored.id}\n`;
  return `${id}event: ${stored.event.type}\ndata: ${JSON.stringify(stored.event)}\n\n`;
}

export function buildMockServer(options: MockOptions = {}): MockServer {
  const clock = new MockClock(options.startAt ?? defaultStart(new Date()));
  const lance = new MockLance({
    clock,
    scenario: options.scenario ?? 'normal',
    actionDelayMs: options.actionDelayMs ?? 250,
  });
  const heartbeatIntervalMs = options.heartbeatIntervalMs ?? 25_000;
  const streams = new Set<() => void>();
  const app = Fastify({
    logger: options.logLevel === undefined ? false : { level: options.logLevel },
    // Shutdown must not wait for a client's idle keep-alive connection.
    forceCloseConnections: true,
  });

  app.addContentTypeParser('application/json', { parseAs: 'string' }, (_request, body, done) => {
    const text = typeof body === 'string' ? body : body.toString('utf8');
    if (text.trim() === '') {
      done(null, undefined);
      return;
    }
    try {
      done(null, JSON.parse(text) as unknown);
    } catch {
      done(new MockError(400, 'Bad request', 'The request body is not valid JSON.'), undefined);
    }
  });

  app.setErrorHandler((error, _request, reply) => {
    if (error instanceof MockError) return sendProblem(reply, error);
    const status = clientErrorStatus(error);
    if (status !== undefined) {
      const message = error instanceof Error ? error.message : 'The request was refused.';
      return sendProblem(reply, new MockError(status, 'Bad request', message));
    }
    app.log.error({ err: error }, 'unhandled error');
    return sendProblem(
      reply,
      new MockError(
        500,
        'Mock error',
        'The mock failed unexpectedly. Check its log and report it.',
      ),
    );
  });

  app.setNotFoundHandler((request, reply) =>
    sendProblem(
      reply,
      new MockError(404, 'Not found', `${request.method} ${request.url} is not a route.`),
    ),
  );

  app.register(
    (v1, _options, done) => {
      v1.addHook('onRequest', async (request: FastifyRequest, reply: FastifyReply) => {
        if (lance.scenario === 'offline') {
          reply.hijack();
          request.raw.socket.destroy();
          return;
        }
        if (!BEARER.test(request.headers.authorization ?? '')) {
          return sendProblem(
            reply,
            new MockError(
              401,
              'Unauthorized',
              'Send an Authorization header of the form "Bearer dev-<anything>".',
            ),
          );
        }
        const version = request.headers['desktop-client-version'];
        if (version === undefined) return;
        // A malformed value is treated as absent: the contract does not define 400 everywhere.
        const parsed = zVersion.safeParse(version);
        if (!parsed.success) return;
        const minimum = lance.currentMinClientVersion;
        if (compareVersions(parsed.data, minimum) < 0) {
          return sendProblem(
            reply,
            new MockError(
              426,
              'Upgrade required',
              `This client is ${parsed.data}; the server needs ${minimum} or later. Update Ian.`,
              { minClientVersion: minimum },
            ),
          );
        }
      });

      v1.get('/me', () => lance.me());
      v1.get('/snapshot', () => lance.snapshot());
      v1.get('/today', () => lance.today());

      v1.get('/items', (request) => {
        const raw = { ...(request.query as Record<string, unknown>) };
        if (typeof raw.limit === 'string') raw.limit = Number(raw.limit);
        return lance.listItems(parseWith(zListItemsQuery, raw));
      });

      v1.get('/items/:itemId', (request) => {
        const { itemId } = request.params as { itemId: string };
        const idPattern = zGetItemPath.shape.itemId.safeParse(itemId);
        const item = idPattern.success ? lance.item(itemId) : undefined;
        if (!item) throw new MockError(404, 'Not found', `No open item has the id ${itemId}.`);
        return item;
      });

      v1.post('/items/:itemId/actions/:actionId', (request, reply) => {
        const body = parseWith(zRunItemActionBody, request.body);
        const { itemId, actionId } = parseWith(zRunItemActionPath, request.params);
        const { status, correlationId } = lance.runAction(itemId, actionId, body);
        return reply.status(status).send({ correlationId });
      });

      v1.post('/handoff', (request, reply) => {
        const body = parseWith(zHandOffBody, request.body);
        const { correlationId } = lance.handOff(body.itemId, body.instruction);
        return reply.status(202).send({ correlationId });
      });

      v1.get('/agents', () => lance.agentsOverview());
      v1.post('/agents/:agentId/pause', (request) =>
        lance.setAgentPaused(parseWith(zPauseAgentPath, request.params).agentId, true),
      );
      v1.post('/agents/:agentId/resume', (request) =>
        lance.setAgentPaused(parseWith(zPauseAgentPath, request.params).agentId, false),
      );

      v1.get('/settings', () => lance.settingsView());
      v1.patch('/settings', (request) => {
        const patch = parseWith(zUpdateSettingsBody, request.body);
        if (Object.keys(patch).length === 0) {
          throw new MockError(
            400,
            'Bad request',
            'Send at least one of quietHours, pushBudgetPerHour, mode, paused or pausedReason.',
          );
        }
        return lance.patchSettings(patch);
      });

      v1.post('/sessions', (request, reply) => {
        lance.recordSession(parseWith(zRecordSessionBody, request.body));
        return reply.status(204).send();
      });

      v1.get('/events', (request, reply) => {
        const header = request.headers['last-event-id'];
        let replay: StoredEvent[] = [];
        if (header !== undefined) {
          const id = zEventId.safeParse(header);
          const held = id.success ? lance.log.replayAfter(Number(id.data)) : null;
          if (held === null) {
            throw new MockError(
              410,
              'Gone',
              `The server does not hold event ${String(header)}. Fetch the snapshot again and resume from its cursor.`,
            );
          }
          replay = held;
        }
        reply.hijack();
        const raw = reply.raw;
        raw.writeHead(200, {
          'content-type': 'text/event-stream',
          'cache-control': 'no-cache, no-transform',
          'x-content-type-options': 'nosniff',
          connection: 'keep-alive',
        });
        // Bytes at once, so a client that waits for the first body bytes reports the stream live.
        raw.write(': open\n\n');
        const write = (stored: StoredEvent): void => {
          raw.write(formatEvent(stored));
        };
        replay.forEach(write);
        const unsubscribe = lance.log.subscribe(write);
        const timer = setInterval(() => {
          write({ id: null, event: { type: 'heartbeat', serverTime: clock.now().toISOString() } });
        }, heartbeatIntervalMs);
        const close = (): void => {
          clearInterval(timer);
          unsubscribe();
          streams.delete(close);
          raw.destroy();
        };
        streams.add(close);
        raw.on('close', close);
      });

      done();
    },
    { prefix: '/desktop/v1' },
  );

  app.post('/__mock/scenario', (request) => {
    const { scenario } = parseWith(zScenarioRequest, request.body);
    lance.loadScenario(scenario);
    if (scenario === 'offline')
      streams.forEach((close) => {
        close();
      });
    return { scenario: lance.scenario, latestEventId: lance.log.latestId() };
  });

  app.get('/__mock/state', () => ({
    scenario: lance.scenario,
    now: clock.now().toISOString(),
    latestEventId: lance.log.latestId(),
    openStreams: streams.size,
    minClientVersion: lance.currentMinClientVersion,
  }));

  app.post('/__mock/emit', (request) => {
    const body = parseWith(zEmitRequest, request.body);
    const before = lance.log.latestId();
    let itemId: string | undefined;
    if ('event' in body) lance.emitRaw(body.event);
    else if (body.recipe === 'alert') itemId = lance.raiseAlert(body).id;
    else itemId = lance.raiseProposal(body).id;
    return {
      events: lance.log.latestId() - before,
      latestEventId: lance.log.latestId(),
      ...(itemId === undefined ? {} : { itemId }),
    };
  });

  app.post('/__mock/clock', (request) => {
    const body = parseWith(zClockRequest, request.body);
    return lance.moveClock(
      'set' in body ? { set: new Date(body.set) } : { advanceMs: body.advanceSeconds * 1000 },
    );
  });

  app.post('/__mock/capabilities', (request) => {
    const { handoff } = parseWith(zCapabilitiesRequest, request.body);
    lance.setHandoffOffered(handoff);
    return { handoff };
  });

  app.get('/__mock/sessions', () => ({ sessions: lance.sessions }));

  return {
    app,
    lance,
    dropStreams: () => {
      streams.forEach((close) => {
        close();
      });
    },
    openStreamCount: () => streams.size,
  };
}
