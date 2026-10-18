import { z } from 'zod';
import { MockError } from '../domain/errors.js';
import { SCENARIOS } from '../domain/types.js';
import { zDateTime, zSeverity, zStreamEvent } from '../generated/zod.gen.js';

export const zScenarioRequest = z.object({ scenario: z.enum(SCENARIOS) });

/**
 * Either a contract event, sent as given and without touching the mock's state, or a recipe
 * that changes the mock's state and lets the events follow.
 */
export const zEmitRequest = z.union([
  z.object({ event: zStreamEvent }),
  z.object({
    recipe: z.literal('alert'),
    severity: zSeverity.default('P1'),
    title: z.string().min(1).max(200).optional(),
  }),
  z.object({
    recipe: z.literal('proposal'),
    expiresInMinutes: z.number().positive().max(10_080).default(60),
    title: z.string().min(1).max(200).optional(),
  }),
]);

export const zClockRequest = z.union([
  z.object({ set: zDateTime }),
  z.object({ advanceSeconds: z.number().int().min(1).max(31_536_000) }),
]);

export function parseWith<Schema extends z.ZodType>(
  schema: Schema,
  value: unknown,
): z.output<Schema> {
  const result = schema.safeParse(value);
  if (result.success) return result.data;
  const detail = result.error.issues
    .slice(0, 5)
    .map((issue) => `${issue.path.join('.') || 'request'}: ${issue.message}`)
    .join('; ');
  throw new MockError(400, 'Bad request', detail);
}
