import type { Item } from './types.js';

/** A refusal the HTTP layer turns into an `application/problem+json` response. */
export class MockError extends Error {
  constructor(
    readonly status: number,
    readonly title: string,
    readonly detail: string,
    readonly extensions: { item?: Item; minClientVersion?: string } = {},
  ) {
    super(detail);
    this.name = 'MockError';
  }
}
