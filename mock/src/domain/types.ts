import type { z } from 'zod';
import type * as g from '../generated/zod.gen.js';

export type Item = z.infer<typeof g.zItem>;
export type ItemKind = z.infer<typeof g.zItemKind>;
export type ItemAction = z.infer<typeof g.zItemAction>;
export type ItemDetail = z.infer<typeof g.zItemDetail>;
export type ProposalDetail = z.infer<typeof g.zProposalDetail>;
export type CommitmentDetail = z.infer<typeof g.zCommitmentDetail>;
export type TaskDetail = z.infer<typeof g.zTaskDetail>;
export type AlertDetail = z.infer<typeof g.zAlertDetail>;
export type Horizon = z.infer<typeof g.zHorizon>;
export type Severity = z.infer<typeof g.zSeverity>;
export type Attention = z.infer<typeof g.zAttention>;
export type Unit = z.infer<typeof g.zUnit>;
export type Today = z.infer<typeof g.zToday>;
export type Views = z.infer<typeof g.zViews>;
export type Agent = z.infer<typeof g.zAgent>;
export type AgentsOverview = z.infer<typeof g.zAgentsOverview>;
export type Settings = z.infer<typeof g.zSettings>;
export type Snapshot = z.infer<typeof g.zSnapshot>;
export type Me = z.infer<typeof g.zMe>;
export type StreamEvent = z.infer<typeof g.zStreamEvent>;
export type SessionHeartbeat = z.infer<typeof g.zSessionHeartbeat>;

export const SCENARIOS = [
  'quiet',
  'normal',
  'overloaded',
  'incident',
  'offline',
  'stale-client',
  'external-meeting',
] as const;
export type Scenario = (typeof SCENARIOS)[number];

/**
 * What the mock holds for one item. The client-facing `Item` is rendered from it against the mock
 * clock, so horizon, pressure, attention and the meta line move when time does.
 */
export interface ItemRecord {
  id: string;
  kind: ItemKind;
  title: string;
  /** The part of the meta line that does not depend on time, such as the counterparty. */
  metaBase: string;
  unit: Unit;
  dueAt: Date | null;
  severity?: Severity;
  working: boolean;
  version: number;
  actions: ItemAction[];
  detail: ItemDetail;
  links: { lance: string; source: string | null };
  /** Set on a proposal the mock raised for another item: what its approval or rejection settles. */
  follows?: { itemId: string; purpose: 'complete_task' | 'chase' };
  /** Risk language in the item's source puts it on the urgent rung (spec 6.6). */
  riskLanguage?: boolean;
}
