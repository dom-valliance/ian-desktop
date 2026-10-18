import { z } from 'zod';
import { SCENARIOS } from './domain/types.js';
import { zDateTime } from './generated/zod.gen.js';

const zEnvironment = z.object({
  MOCK_PORT: z.coerce.number().int().min(0).max(65_535).default(4317),
  MOCK_HOST: z.string().min(1).default('127.0.0.1'),
  MOCK_SCENARIO: z.enum(SCENARIOS).default('normal'),
  MOCK_START_AT: zDateTime.optional(),
  MOCK_HEARTBEAT_INTERVAL_MS: z.coerce.number().int().positive().default(25_000),
  MOCK_ACTION_DELAY_MS: z.coerce.number().int().min(0).default(250),
  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace', 'silent']).default('info'),
});

export type MockConfig = z.infer<typeof zEnvironment>;

/** Reads the mock's configuration from the environment, refusing values it cannot use. */
export function loadConfig(environment: NodeJS.ProcessEnv): MockConfig {
  const parsed = zEnvironment.safeParse(environment);
  if (!parsed.success) {
    const problems = parsed.error.issues.map(
      (issue) => `${issue.path.join('.')}: ${issue.message}`,
    );
    throw new Error(`Invalid mock configuration. ${problems.join('; ')}`);
  }
  return parsed.data;
}

/** The mock clock starts at 09:30 UTC on the current date, so quiet hours never hide the demo. */
export function defaultStart(now: Date): Date {
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate(), 9, 30, 0, 0));
}
