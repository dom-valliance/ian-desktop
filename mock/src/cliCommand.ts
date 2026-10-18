export interface MockRequest {
  method: 'GET' | 'POST';
  path: string;
  body?: unknown;
}

export class UsageError extends Error {}

export const USAGE = `Usage: pnpm mock <command>

  emit alert [--severity P0|P1|P2|P3] [--title <text>]
  emit proposal [--expires-in <minutes>] [--title <text>]
  emit event '<StreamEvent JSON>'
  scenario <quiet|normal|overloaded|incident|offline|stale-client|external-meeting>
  clock set <UTC time such as 2026-10-16T09:30:00.000Z>
  clock advance <30s|15m|2h|1d>
  sessions
  state

The mock is read from MOCK_URL, by default http://127.0.0.1:4317.`;

const UNIT_SECONDS = { s: 1, m: 60, h: 3600, d: 86_400 } as const;

/** Seconds in a duration such as `90s`, `15m`, `2h` or `1d`. */
export function parseDuration(text: string): number {
  const match = /^(\d+)([smhd])$/.exec(text);
  if (!match)
    throw new UsageError(
      `"${text}" is not a duration. Use a number and s, m, h or d, such as 15m.`,
    );
  const [, amount, unit] = match;
  return Number(amount) * UNIT_SECONDS[unit as keyof typeof UNIT_SECONDS];
}

function flags(args: string[]): Map<string, string> {
  const found = new Map<string, string>();
  for (let i = 0; i < args.length; i += 2) {
    const name = args[i];
    const value = args[i + 1];
    if (!name?.startsWith('--') || value === undefined) {
      throw new UsageError(`Expected "--name value" pairs, found "${name ?? ''}".`);
    }
    found.set(name.slice(2), value);
  }
  return found;
}

function only(found: Map<string, string>, allowed: string[]): void {
  for (const name of found.keys()) {
    if (!allowed.includes(name))
      throw new UsageError(
        `Unknown flag --${name}. Allowed: ${allowed.map((a) => `--${a}`).join(', ')}.`,
      );
  }
}

/** Turns command-line arguments into the one request they stand for. */
export function parseCommand(argv: string[]): MockRequest {
  const [command, subject, ...rest] = argv;
  switch (command) {
    case 'emit': {
      if (subject === 'event') {
        const [json] = rest;
        if (json === undefined)
          throw new UsageError('emit event needs a StreamEvent as JSON, in quotes.');
        try {
          return {
            method: 'POST',
            path: '/__mock/emit',
            body: { event: JSON.parse(json) as unknown },
          };
        } catch {
          throw new UsageError('The event is not valid JSON.');
        }
      }
      const found = flags(rest);
      if (subject === 'alert') {
        only(found, ['severity', 'title']);
        const severity = found.get('severity');
        const title = found.get('title');
        return {
          method: 'POST',
          path: '/__mock/emit',
          body: {
            recipe: 'alert',
            ...(severity === undefined ? {} : { severity }),
            ...(title === undefined ? {} : { title }),
          },
        };
      }
      if (subject === 'proposal') {
        only(found, ['expires-in', 'title']);
        const expires = found.get('expires-in');
        const title = found.get('title');
        return {
          method: 'POST',
          path: '/__mock/emit',
          body: {
            recipe: 'proposal',
            ...(expires === undefined ? {} : { expiresInMinutes: Number(expires) }),
            ...(title === undefined ? {} : { title }),
          },
        };
      }
      throw new UsageError('emit takes alert, proposal or event.');
    }
    case 'scenario':
      if (subject === undefined) throw new UsageError('scenario needs a name.');
      return { method: 'POST', path: '/__mock/scenario', body: { scenario: subject } };
    case 'clock': {
      const [value] = rest;
      if (subject === 'set' && value !== undefined) {
        return { method: 'POST', path: '/__mock/clock', body: { set: value } };
      }
      if (subject === 'advance' && value !== undefined) {
        return {
          method: 'POST',
          path: '/__mock/clock',
          body: { advanceSeconds: parseDuration(value) },
        };
      }
      throw new UsageError('clock takes "set <time>" or "advance <duration>".');
    }
    case 'sessions':
      return { method: 'GET', path: '/__mock/sessions' };
    case 'state':
      return { method: 'GET', path: '/__mock/state' };
    default:
      throw new UsageError(
        command === undefined ? 'Give a command.' : `Unknown command "${command}".`,
      );
  }
}
