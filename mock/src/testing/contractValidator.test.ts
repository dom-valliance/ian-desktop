import { describe, expect, it } from 'vitest';
import { MOCK_CONTRACT_VERSION } from '../domain/seeds.js';
import { ContractValidator } from './contractValidator.js';

const validator = new ContractValidator();

const validMe = {
  principalId: 'prin_1',
  displayName: '[PERSON]',
  status: 'active',
  mode: 'dry_run',
  timeZone: 'Europe/London',
  minClientVersion: '0.1.0',
  contractVersion: MOCK_CONTRACT_VERSION,
  capabilities: { handoff: true },
  serverTime: '2026-10-16T08:00:00.000Z',
};

describe('the contract version', () => {
  it('is the version the mock reports in /me', () => {
    expect(MOCK_CONTRACT_VERSION).toBe(validator.version);
  });
});

describe('the contract validator', () => {
  it('accepts a body that satisfies the response schema', () => {
    const result = validator.validateResponse('get', '/me', 200, 'application/json', validMe);
    expect(result.errors).toEqual([]);
  });

  it('rejects a body with a missing required field', () => {
    const incomplete: Record<string, unknown> = { ...validMe };
    delete incomplete.serverTime;
    const result = validator.validateResponse('get', '/me', 200, 'application/json', incomplete);
    expect(result.ok).toBe(false);
    expect(result.errors.join(' ')).toContain('serverTime');
  });

  it('rejects a time without milliseconds', () => {
    const result = validator.validateResponse('get', '/me', 200, 'application/json', {
      ...validMe,
      serverTime: '2026-10-16T08:00:00Z',
    });
    expect(result.ok).toBe(false);
  });

  it('rejects a status the contract does not define for the operation', () => {
    const result = validator.validateResponse('get', '/me', 404, 'application/problem+json', {});
    expect(result.ok).toBe(false);
    expect(result.errors.join(' ')).toContain('no such status');
  });

  it('rejects a content type the contract does not define', () => {
    const result = validator.validateResponse('get', '/me', 200, 'text/plain', validMe);
    expect(result.ok).toBe(false);
  });

  it('validates problem bodies through a shared response reference', () => {
    const problem = { type: 'about:blank', title: 'Unauthorized', status: 401, detail: 'Sign in.' };
    expect(
      validator.validateResponse('get', '/me', 401, 'application/problem+json', problem).errors,
    ).toEqual([]);
    expect(
      validator.validateResponse('get', '/me', 426, 'application/problem+json', problem).ok,
    ).toBe(false);
  });

  it('accepts an empty body where the contract defines no content', () => {
    expect(validator.validateResponse('post', '/sessions', 204, null, '').ok).toBe(true);
    expect(validator.validateResponse('post', '/sessions', 204, null, { a: 1 }).ok).toBe(false);
  });

  it('treats a discriminator as an annotation and still picks the union member by its enum', () => {
    const heartbeat = { type: 'heartbeat', serverTime: '2026-10-16T08:00:25.000Z' };
    expect(validator.validateSchema('StreamEvent', heartbeat).errors).toEqual([]);
    expect(validator.validateSchema('StreamEvent', { type: 'heartbeat' }).ok).toBe(false);
    expect(validator.validateSchema('StreamEvent', { type: 'unknown.event' }).ok).toBe(false);
  });

  it('lists every operation in the contract', () => {
    const ids = validator.operations().map((operation) => operation.operationId);
    expect(ids).toContain('getSnapshot');
    expect(ids).toContain('streamEvents');
    expect(ids).toHaveLength(14);
  });
});
