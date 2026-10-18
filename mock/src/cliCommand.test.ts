import { describe, expect, it } from 'vitest';
import { UsageError, parseCommand, parseDuration } from './cliCommand.js';

describe('the mock CLI', () => {
  it('turns "emit alert --severity P1" into the alert recipe', () => {
    expect(parseCommand(['emit', 'alert', '--severity', 'P1'])).toEqual({
      method: 'POST',
      path: '/__mock/emit',
      body: { recipe: 'alert', severity: 'P1' },
    });
  });

  it('turns a proposal with an expiry into its recipe', () => {
    expect(
      parseCommand(['emit', 'proposal', '--expires-in', '10', '--title', 'A title']).body,
    ).toEqual({
      recipe: 'proposal',
      expiresInMinutes: 10,
      title: 'A title',
    });
  });

  it('passes a raw event through as given', () => {
    const event = { type: 'heartbeat', serverTime: '2026-10-16T09:00:00.000Z' };
    expect(parseCommand(['emit', 'event', JSON.stringify(event)]).body).toEqual({ event });
  });

  it('sets a scenario, moves the clock and reads sessions and state', () => {
    expect(parseCommand(['scenario', 'incident']).body).toEqual({ scenario: 'incident' });
    expect(parseCommand(['clock', 'advance', '2h']).body).toEqual({ advanceSeconds: 7200 });
    expect(parseCommand(['clock', 'set', '2026-10-16T09:30:00.000Z']).body).toEqual({
      set: '2026-10-16T09:30:00.000Z',
    });
    expect(parseCommand(['sessions'])).toEqual({ method: 'GET', path: '/__mock/sessions' });
    expect(parseCommand(['state']).path).toBe('/__mock/state');
  });

  it.each([
    [[]],
    [['dance']],
    [['emit', 'alert', '--colour', 'red']],
    [['emit', 'alert', '--severity']],
    [['emit', 'event', 'not json']],
    [['clock', 'advance', 'soon']],
    [['scenario']],
  ])('refuses %j with a message that says what to do', (argv) => {
    expect(() => parseCommand(argv)).toThrow(UsageError);
  });

  it('reads durations in seconds, minutes, hours and days', () => {
    expect([
      parseDuration('30s'),
      parseDuration('15m'),
      parseDuration('2h'),
      parseDuration('1d'),
    ]).toEqual([30, 900, 7200, 86_400]);
  });
});
