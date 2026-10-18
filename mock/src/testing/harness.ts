import type { AddressInfo } from 'node:net';
import { buildMockServer, type MockOptions, type MockServer } from '../http/app.js';
import { ContractValidator } from './contractValidator.js';

export const START = new Date('2026-10-16T09:00:00.000Z');
export const AUTH = { authorization: 'Bearer dev-test' };
export const validator = new ContractValidator();

export interface Reply {
  status: number;
  contentType: string | null;
  body: unknown;
}

export interface Harness {
  server: MockServer;
  origin: string;
  call: (method: string, path: string, options?: CallOptions) => Promise<Reply>;
  close: () => Promise<void>;
}

export interface CallOptions {
  body?: unknown;
  headers?: Record<string, string>;
  /** Defaults to a valid bearer token. */
  auth?: boolean;
}

export async function startHarness(options: MockOptions = {}): Promise<Harness> {
  const server = buildMockServer({
    startAt: START,
    actionDelayMs: 0,
    heartbeatIntervalMs: 60_000,
    ...options,
  });
  await server.app.listen({ host: '127.0.0.1', port: 0 });
  const { port } = server.app.server.address() as AddressInfo;
  const origin = `http://127.0.0.1:${String(port)}`;

  async function call(method: string, path: string, init: CallOptions = {}): Promise<Reply> {
    const headers: Record<string, string> = {
      ...(init.auth === false ? {} : AUTH),
      ...init.headers,
    };
    if (init.body !== undefined) headers['content-type'] = 'application/json';
    const response = await fetch(`${origin}${path}`, {
      method,
      headers,
      ...(init.body === undefined ? {} : { body: JSON.stringify(init.body) }),
    });
    const text = await response.text();
    const contentType = response.headers.get('content-type');
    const body: unknown = text === '' ? undefined : JSON.parse(text);
    return { status: response.status, contentType, body };
  }

  return {
    server,
    origin,
    call,
    close: async () => {
      server.dropStreams();
      await server.lance.idle();
      await server.app.close();
    },
  };
}

export interface StreamedEvent {
  id: string | null;
  event: string;
  data: unknown;
}

export interface EventStream {
  status: number;
  /** Reads until `count` more events have arrived. */
  next: (count: number, timeoutMs?: number) => Promise<StreamedEvent[]>;
  close: () => void;
}

function parseBlock(block: string): StreamedEvent | null {
  let id: string | null = null;
  let event = '';
  let data = '';
  for (const line of block.split('\n')) {
    if (line.startsWith('id: ')) id = line.slice(4);
    else if (line.startsWith('event: ')) event = line.slice(7);
    else if (line.startsWith('data: ')) data += line.slice(6);
  }
  return event === '' ? null : { id, event, data: JSON.parse(data) as unknown };
}

/** Opens `GET /events`. A refused request has status 410 and no events. */
export async function openStream(
  harness: Harness,
  options: { lastEventId?: string } = {},
): Promise<EventStream> {
  const controller = new AbortController();
  const response = await fetch(`${harness.origin}/desktop/v1/events`, {
    headers: {
      ...AUTH,
      ...(options.lastEventId === undefined ? {} : { 'last-event-id': options.lastEventId }),
    },
    signal: controller.signal,
  });
  const reader = response.body?.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  const queue: StreamedEvent[] = [];

  // One read stays in flight across calls, so a timeout never discards bytes that arrive later.
  let inFlight: ReturnType<ReadableStreamDefaultReader<Uint8Array>['read']> | undefined;

  async function fill(timeoutMs: number): Promise<boolean> {
    if (!reader) return false;
    inFlight ??= reader.read();
    const timeout = new Promise<'timeout'>((resolve) => {
      setTimeout(() => {
        resolve('timeout');
      }, timeoutMs);
    });
    const result = await Promise.race([inFlight, timeout]);
    if (result === 'timeout') return false;
    inFlight = undefined;
    if (result.done) return false;
    buffer += decoder.decode(result.value, { stream: true });
    let boundary = buffer.indexOf('\n\n');
    while (boundary !== -1) {
      const parsed = parseBlock(buffer.slice(0, boundary));
      if (parsed) queue.push(parsed);
      buffer = buffer.slice(boundary + 2);
      boundary = buffer.indexOf('\n\n');
    }
    return true;
  }

  return {
    status: response.status,
    async next(count, timeoutMs = 3000) {
      const deadline = Date.now() + timeoutMs;
      while (queue.length < count && Date.now() < deadline) {
        if (!(await fill(Math.max(1, deadline - Date.now())))) break;
      }
      return queue.splice(0, count);
    },
    close() {
      controller.abort();
    },
  };
}

export function expectContract(
  method: string,
  path: string,
  reply: Reply,
  expectedStatus: number,
): void {
  if (reply.status !== expectedStatus) {
    throw new Error(
      `${method} ${path}: expected ${String(expectedStatus)}, got ${String(reply.status)} ${JSON.stringify(reply.body)}`,
    );
  }
  const result = validator.validateResponse(
    method.toLowerCase(),
    path,
    reply.status,
    reply.contentType,
    reply.body,
  );
  if (!result.ok) throw new Error(result.errors.slice(0, 8).join('\n'));
}
