import type {
  AlertDetail,
  CommitmentDetail,
  ItemAction,
  ItemRecord,
  ProposalDetail,
  Severity,
  TaskDetail,
  Unit,
} from './types.js';

export const OTHER_UNIT: Unit = { id: 'other', name: 'Other' };

const LANCE_BASE = 'https://lance.example.invalid';

const action = (
  id: string,
  label: string,
  style: ItemAction['style'],
  input: ItemAction['input'] = 'none',
  confirm: string | null = null,
): ItemAction => ({ id, label, style, confirm, input });

export const PROPOSAL_ACTIONS: ItemAction[] = [
  action('approve', 'Approve', 'primary'),
  action('reject', 'Reject', 'secondary', 'none', 'Reject this proposal?'),
];
export const COMMITMENT_BY_ACTIONS: ItemAction[] = [
  action('settle', 'Settle', 'primary'),
  action('snooze', 'Snooze', 'quiet', 'until'),
  action('dismiss', 'Dismiss', 'quiet', 'none', 'Dismiss this commitment?'),
];
export const COMMITMENT_TO_ACTIONS: ItemAction[] = [
  action('settle', 'Received', 'primary'),
  action('chase', 'Chase', 'secondary', 'note'),
  action('snooze', 'Snooze', 'quiet', 'until'),
];
export const TO_CONFIRM_ACTIONS: ItemAction[] = [
  action('confirm', 'Confirm', 'primary'),
  action('dismiss', 'Dismiss', 'quiet', 'none', 'Dismiss this commitment?'),
];
export const TASK_ACTIONS: ItemAction[] = [action('done', 'Done', 'primary')];
export const ALERT_ACTIONS: ItemAction[] = [
  action('acknowledge', 'Acknowledge', 'primary'),
  action('snooze', 'Snooze', 'quiet', 'until'),
];

export interface ProposalSpec {
  title: string;
  summary: string;
  actionClass: string;
  actionClassLabel: string;
  targetSystem: string;
  targetSystemLabel: string;
  unit: Unit;
  expiresAt: Date;
  confidence?: ProposalDetail['confidence'];
  decisionTier?: ProposalDetail['decisionTier'];
  working?: boolean;
  follows?: ItemRecord['follows'];
  riskLanguage?: boolean;
}

export function proposalRecord(id: string, spec: ProposalSpec): ItemRecord {
  const detail: ProposalDetail = {
    kind: 'proposal',
    actionClass: spec.actionClass,
    actionClassLabel: spec.actionClassLabel,
    targetSystem: spec.targetSystem,
    targetSystemLabel: spec.targetSystemLabel,
    summary: spec.summary,
    policyDecision: 'propose',
    decisionTier: spec.decisionTier ?? 'personal',
    expiresAt: spec.expiresAt.toISOString(),
  };
  if (spec.confidence !== undefined) detail.confidence = spec.confidence;
  const record: ItemRecord = {
    id,
    kind: 'proposal',
    title: spec.title,
    metaBase: `${spec.unit.name}, ${spec.actionClassLabel.toLowerCase()}`,
    unit: spec.unit,
    dueAt: null,
    working: spec.working ?? false,
    version: 1,
    actions: PROPOSAL_ACTIONS,
    detail,
    links: { lance: `${LANCE_BASE}/proposals/${id}`, source: null },
  };
  if (spec.follows !== undefined) record.follows = spec.follows;
  if (spec.riskLanguage === true) record.riskLanguage = true;
  return record;
}

export interface CommitmentSpec {
  direction: 'commitment_by' | 'commitment_to';
  title: string;
  counterparty: { id: string; name: string };
  unit: Unit;
  dueAt: Date | null;
  quote: string;
  source: { kind: 'email' | 'meeting' | 'record'; system: string; label: string; observedAt: Date };
  toConfirm?: boolean;
  chase?: { count: number; lastChasedAt: Date };
}

export function commitmentRecord(id: string, spec: CommitmentSpec): ItemRecord {
  const toConfirm = spec.toConfirm ?? false;
  const detail: CommitmentDetail = {
    kind: spec.direction,
    counterparty: spec.counterparty,
    evidence: {
      quote: spec.quote,
      source: {
        kind: spec.source.kind,
        system: spec.source.system,
        label: spec.source.label,
        observedAt: spec.source.observedAt.toISOString(),
      },
    },
    chase:
      spec.chase === undefined
        ? { state: 'not_chased', count: 0, lastChasedAt: null, nextChaseAt: null }
        : {
            state: 'chased',
            count: spec.chase.count,
            lastChasedAt: spec.chase.lastChasedAt.toISOString(),
            nextChaseAt: null,
          },
    toConfirm,
  };
  let actions = spec.direction === 'commitment_by' ? COMMITMENT_BY_ACTIONS : COMMITMENT_TO_ACTIONS;
  if (toConfirm) actions = TO_CONFIRM_ACTIONS;
  return {
    id,
    kind: spec.direction,
    title: spec.title,
    metaBase: `${spec.counterparty.name} at ${spec.unit.name}`,
    unit: spec.unit,
    dueAt: spec.dueAt,
    working: false,
    version: 1,
    actions,
    detail,
    links: { lance: `${LANCE_BASE}/commitments/${id}`, source: null },
  };
}

export interface TaskSpec {
  title: string;
  unit: Unit;
  dueAt: Date | null;
  source: TaskDetail['source'];
  status: string;
  project: string | null;
  working?: boolean;
  assignee?: TaskDetail['assignee'];
}

export function taskRecord(id: string, spec: TaskSpec): ItemRecord {
  const detail: TaskDetail = {
    kind: 'task',
    source: spec.source,
    assignee: spec.assignee ?? { name: '[PERSON]', isPrincipal: true },
    status: spec.status,
    project: spec.project,
  };
  return {
    id,
    kind: 'task',
    title: spec.title,
    metaBase: spec.source === 'notion' ? 'Notion' : 'Jamie',
    unit: spec.unit,
    dueAt: spec.dueAt,
    working: spec.working ?? false,
    version: 1,
    actions: TASK_ACTIONS,
    detail,
    links: {
      lance: `${LANCE_BASE}/tasks/${id}`,
      source: `https://${spec.source}.example.invalid/${id}`,
    },
  };
}

export interface AlertSpec {
  severity: Severity;
  title: string;
  alertKind: string;
  alertKindLabel: string;
  explanation: string;
  raisedAt: Date;
  dedupeKey: string;
  relatedItemIds?: string[];
}

export function alertRecord(id: string, spec: AlertSpec): ItemRecord {
  const detail: AlertDetail = {
    kind: 'alert',
    alertKind: spec.alertKind,
    alertKindLabel: spec.alertKindLabel,
    raisedAt: spec.raisedAt.toISOString(),
    dedupeKey: spec.dedupeKey,
    relatedItemIds: spec.relatedItemIds ?? [],
    explanation: spec.explanation,
  };
  return {
    id,
    kind: 'alert',
    title: spec.title,
    metaBase: spec.severity,
    unit: OTHER_UNIT,
    dueAt: null,
    severity: spec.severity,
    working: false,
    version: 1,
    actions: ALERT_ACTIONS,
    detail,
    links: { lance: `${LANCE_BASE}/alerts/${id}`, source: null },
  };
}
