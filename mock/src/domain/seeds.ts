// Invented scenario data. Units, people and titles are placeholders; nothing here comes from a
// real mailbox, calendar, meeting or task list (AGENTS.md, Data).
import {
  OTHER_UNIT,
  alertRecord,
  commitmentRecord,
  proposalRecord,
  taskRecord,
  type CommitmentSpec,
  type ProposalSpec,
} from './factories.js';
import { HOUR_MS, MINUTE_MS } from './time.js';
import type { Agent, ItemRecord, Scenario, Settings, Unit } from './types.js';

const unit = (id: string, name: string): Unit => ({ id, name });
const CLIENT_A = unit('unit_client_a', '[CLIENT A]');
const CLIENT_B = unit('unit_client_b', '[CLIENT B]');
const CLIENT_C = unit('unit_client_c', '[CLIENT C]');
const CLIENT_D = unit('unit_client_d', '[CLIENT D]');
const INTERNAL = unit('unit_internal', 'Internal operations');
const HIRING = unit('unit_hiring', 'Hiring');

const person = (letter: string): { id: string; name: string } => ({
  id: `person_000${letter.charCodeAt(0) - 64}`,
  name: `[PERSON ${letter}]`,
});

const PRINCIPAL_ID = 'prin_01JAXQ0000PRINCIPAL0000001';
export const MOCK_CONTRACT_VERSION = '1.0.1';
export const DEFAULT_MIN_CLIENT_VERSION = '0.1.0';
export const STALE_MIN_CLIENT_VERSION = '99.0.0';
export const PRINCIPAL = { principalId: PRINCIPAL_ID, displayName: '[PERSON]' } as const;
const TIME_ZONE = 'Europe/London';

const pad = (n: number): string => String(n).padStart(12, '0');
const itemId = (prefix: string, n: number): string => `${prefix}_01MOCK${pad(n)}`;

type Offset = (hours: number) => Date;

function proposalPool(at: Offset): ProposalSpec[] {
  const minutes = (m: number): Date => new Date(at(0).getTime() + m * MINUTE_MS);
  const draft = {
    actionClass: 'draft_email',
    actionClassLabel: 'Draft email',
    targetSystem: 'graph',
    targetSystemLabel: 'Outlook',
  };
  const invite = {
    actionClass: 'send_calendar_invite',
    actionClassLabel: 'Calendar invite',
    targetSystem: 'graph',
    targetSystemLabel: 'Outlook calendar',
  };
  const notion = { targetSystem: 'notion', targetSystemLabel: 'Notion' };
  return [
    {
      ...draft,
      title: 'Send the revised scope to [CLIENT A]',
      summary: 'A reply to [PERSON A] with the revised scope attached.',
      unit: CLIENT_A,
      expiresAt: minutes(12),
      confidence: { value: 0.82, source: 'self_report' },
    },
    {
      ...draft,
      title: 'Reply to [PERSON B] about the review date',
      summary: 'A short reply proposing two dates for the review.',
      unit: CLIENT_B,
      expiresAt: minutes(95),
      confidence: { value: 0.9, source: 'lev_trusted' },
      decisionTier: 'organisation',
    },
    {
      ...invite,
      title: 'Move the weekly sync with [CLIENT C] to Thursday',
      summary: 'Move the recurring sync one day later, this week only.',
      unit: CLIENT_C,
      expiresAt: at(3),
      confidence: { value: 0.74, source: 'self_report' },
    },
    {
      actionClass: 'update_task',
      actionClassLabel: 'Update task',
      ...notion,
      title: 'Move the supplier checklist to In Progress',
      summary: 'Change the status of one task from Not started to In Progress.',
      unit: INTERNAL,
      expiresAt: at(5),
      decisionTier: 'fallback',
    },
    {
      actionClass: 'create_task',
      actionClassLabel: 'Create task',
      ...notion,
      title: 'Add a follow-up task for the [CLIENT A] workshop',
      summary: 'A task to send the workshop notes, due on Friday.',
      unit: CLIENT_A,
      expiresAt: at(8),
      confidence: { value: 0.67, source: 'lev_untrusted' },
    },
    {
      ...draft,
      title: 'Draft a thank-you note to [PERSON D]',
      summary: 'Two sentences thanking [PERSON D] for the introduction.',
      unit: CLIENT_D,
      expiresAt: at(26),
    },
    {
      ...invite,
      title: 'Decline the [CLIENT D] planning invite',
      summary: 'Decline with a note that the date clashes.',
      unit: CLIENT_D,
      expiresAt: at(30),
      confidence: { value: 0.88, source: 'lev_trusted' },
    },
    {
      actionClass: 'update_task',
      actionClassLabel: 'Update task',
      ...notion,
      title: 'Move the due date on the budget review',
      summary: 'Move one due date from Monday to Wednesday.',
      unit: INTERNAL,
      expiresAt: at(48),
      decisionTier: 'hard_floor',
    },
    {
      ...draft,
      title: 'Reply to [PERSON C] about the contract draft',
      summary: 'Acknowledge the draft and ask for one more week.',
      unit: HIRING,
      expiresAt: at(70),
      confidence: { value: 0.55, source: 'lev_untrusted' },
    },
  ];
}

function commitmentByPool(at: Offset): CommitmentSpec[] {
  const email = (hoursAgo: number): CommitmentSpec['source'] => ({
    kind: 'email',
    system: 'graph',
    label: 'Email',
    observedAt: at(-hoursAgo),
  });
  const meeting = (hoursAgo: number): CommitmentSpec['source'] => ({
    kind: 'meeting',
    system: 'jamie',
    label: 'Meeting',
    observedAt: at(-hoursAgo),
  });
  const by = 'commitment_by' as const;
  return [
    {
      direction: by,
      title: 'Send [PERSON A] the signed order form',
      counterparty: person('A'),
      unit: CLIENT_A,
      dueAt: at(4),
      quote: 'I will send the signed order form over by Friday.',
      source: email(40),
    },
    {
      direction: by,
      title: 'Share the project plan with [PERSON B]',
      counterparty: person('B'),
      unit: CLIENT_B,
      dueAt: at(6),
      quote: 'I will share the plan once the dates are agreed.',
      source: meeting(22),
    },
    {
      direction: by,
      title: 'Confirm the venue for the [CLIENT B] offsite',
      counterparty: person('B'),
      unit: CLIENT_B,
      dueAt: at(30),
      quote: 'Let me confirm the venue by the end of the week.',
      source: email(60),
    },
    {
      direction: by,
      title: 'Return the reviewed draft to [PERSON C]',
      counterparty: person('C'),
      unit: CLIENT_C,
      dueAt: at(52),
      quote: 'I will return the draft with comments on Wednesday.',
      source: email(30),
    },
    {
      direction: by,
      title: 'Book the follow-up call with [PERSON D]',
      counterparty: person('D'),
      unit: CLIENT_D,
      dueAt: at(80),
      quote: 'I will put a follow-up call in the diary.',
      source: meeting(70),
    },
    {
      direction: by,
      title: 'Send the invoice query to [PERSON A]',
      counterparty: person('A'),
      unit: CLIENT_A,
      dueAt: at(120),
      quote: 'I will raise the invoice query with finance and come back to you.',
      source: email(90),
    },
    {
      direction: by,
      title: 'Finish the onboarding guide for [CLIENT C]',
      counterparty: person('C'),
      unit: CLIENT_C,
      dueAt: at(-20),
      quote: 'The onboarding guide will be with you by the start of the week.',
      source: email(120),
    },
    {
      direction: by,
      title: 'Prepare the quarterly summary for [CLIENT D]',
      counterparty: person('D'),
      unit: CLIENT_D,
      dueAt: at(200),
      quote: 'I will prepare a summary ahead of the quarterly review.',
      source: meeting(48),
    },
  ];
}

function commitmentToPool(at: Offset): CommitmentSpec[] {
  const email = (hoursAgo: number): CommitmentSpec['source'] => ({
    kind: 'email',
    system: 'graph',
    label: 'Email',
    observedAt: at(-hoursAgo),
  });
  const meeting = (hoursAgo: number): CommitmentSpec['source'] => ({
    kind: 'meeting',
    system: 'jamie',
    label: 'Meeting',
    observedAt: at(-hoursAgo),
  });
  const to = 'commitment_to' as const;
  return [
    {
      direction: to,
      title: '[PERSON A] owes the updated forecast',
      counterparty: person('A'),
      unit: CLIENT_A,
      dueAt: at(72),
      quote: 'We will have the updated forecast to you early next week.',
      source: meeting(20),
    },
    {
      direction: to,
      title: '[PERSON B] owes the signed statement of work',
      counterparty: person('B'),
      unit: CLIENT_B,
      dueAt: at(5),
      quote: 'The signed statement of work will come back today.',
      source: email(30),
      chase: { count: 1, lastChasedAt: at(-24) },
    },
    {
      direction: to,
      title: '[PERSON C] owes the access request outcome',
      counterparty: person('C'),
      unit: CLIENT_C,
      dueAt: at(28),
      quote: 'I will confirm the access request tomorrow.',
      source: email(26),
    },
    {
      direction: to,
      title: '[PERSON D] owes the venue shortlist',
      counterparty: person('D'),
      unit: CLIENT_D,
      dueAt: at(100),
      quote: 'A shortlist of venues will follow by Friday.',
      source: meeting(50),
    },
    {
      direction: to,
      title: '[PERSON A] owes feedback on the proposal',
      counterparty: person('A'),
      unit: CLIENT_A,
      dueAt: at(150),
      quote: 'Feedback on the proposal will be with you next week.',
      source: email(72),
    },
    {
      direction: to,
      title: '[PERSON C] owes the revised timeline',
      counterparty: person('C'),
      unit: INTERNAL,
      dueAt: at(-6),
      quote: 'The revised timeline is coming this morning.',
      source: email(34),
      chase: { count: 2, lastChasedAt: at(-3) },
    },
    {
      direction: to,
      title: '[PERSON B] owes the data extract',
      counterparty: person('B'),
      unit: HIRING,
      dueAt: at(240),
      quote: 'The extract will be ready after the audit.',
      source: meeting(96),
    },
  ];
}

function toConfirmPool(at: Offset): CommitmentSpec[] {
  return [
    {
      direction: 'commitment_to',
      title: '[PERSON D] may owe a reference check',
      counterparty: person('D'),
      unit: HIRING,
      dueAt: at(60),
      quote: 'I can get you a reference by the end of next week, if that helps.',
      source: { kind: 'email', system: 'graph', label: 'Email', observedAt: at(-5) },
      toConfirm: true,
    },
    {
      direction: 'commitment_by',
      title: 'You may have offered the workshop slides to [PERSON A]',
      counterparty: person('A'),
      unit: CLIENT_A,
      dueAt: null,
      quote: 'Happy to pass the slides on afterwards.',
      source: { kind: 'meeting', system: 'jamie', label: 'Meeting', observedAt: at(-3) },
      toConfirm: true,
    },
    {
      direction: 'commitment_to',
      title: '[PERSON B] may owe the revised quote',
      counterparty: person('B'),
      unit: CLIENT_B,
      dueAt: at(90),
      quote: 'We should be able to send a revised quote next week.',
      source: { kind: 'email', system: 'graph', label: 'Email', observedAt: at(-8) },
      toConfirm: true,
    },
  ];
}

interface TaskPoolEntry {
  title: string;
  unit: Unit;
  dueHours: number | null;
  source: 'notion' | 'jamie';
  status: string;
  project: string | null;
}

const TASK_POOL: TaskPoolEntry[] = [
  {
    title: 'Draft the agenda for the [CLIENT A] steering group',
    unit: CLIENT_A,
    dueHours: 7,
    source: 'notion',
    status: 'In Progress',
    project: 'Steering group',
  },
  {
    title: 'Review the onboarding checklist',
    unit: INTERNAL,
    dueHours: 20,
    source: 'notion',
    status: 'Not started',
    project: null,
  },
  {
    title: 'Collate feedback from the pilot users',
    unit: CLIENT_B,
    dueHours: null,
    source: 'jamie',
    status: 'Not started',
    project: 'Pilot',
  },
  {
    title: 'Update the risk register',
    unit: INTERNAL,
    dueHours: 50,
    source: 'notion',
    status: 'In Progress',
    project: null,
  },
  {
    title: 'Write up the workshop notes',
    unit: CLIENT_A,
    dueHours: 100,
    source: 'jamie',
    status: 'Not started',
    project: 'Workshop',
  },
  {
    title: 'Check the supplier terms',
    unit: INTERNAL,
    dueHours: 140,
    source: 'notion',
    status: 'Blocked',
    project: null,
  },
  {
    title: 'Plan the team away day',
    unit: HIRING,
    dueHours: null,
    source: 'notion',
    status: 'Not started',
    project: null,
  },
  {
    title: 'Prepare the hiring scorecard',
    unit: HIRING,
    dueHours: 160,
    source: 'notion',
    status: 'In Progress',
    project: 'Hiring',
  },
  {
    title: 'Tidy the shared notes folder',
    unit: OTHER_UNIT,
    dueHours: null,
    source: 'notion',
    status: 'Not started',
    project: null,
  },
  {
    title: 'Schedule the quarterly review',
    unit: CLIENT_D,
    dueHours: 220,
    source: 'jamie',
    status: 'Not started',
    project: 'Quarterly review',
  },
  {
    title: 'Refresh the project brief for [CLIENT B]',
    unit: CLIENT_B,
    dueHours: 28,
    source: 'notion',
    status: 'In Progress',
    project: 'Pilot',
  },
  {
    title: 'Summarise the retrospective actions',
    unit: CLIENT_C,
    dueHours: 300,
    source: 'jamie',
    status: 'Not started',
    project: null,
  },
  {
    title: 'Archive the closed project files',
    unit: OTHER_UNIT,
    dueHours: null,
    source: 'notion',
    status: 'Not started',
    project: null,
  },
  {
    title: 'Outline the training session for [CLIENT C]',
    unit: CLIENT_C,
    dueHours: 90,
    source: 'notion',
    status: 'Not started',
    project: 'Training',
  },
];

const ALERT_POOL = [
  {
    severity: 'P2',
    title: 'The mail watcher is running slowly',
    alertKind: 'watcher_slow',
    alertKindLabel: 'Watcher slow',
    explanation: 'The mail watcher took three times its usual time on the last run.',
    dedupeKey: 'watcher:graph-mail:latency',
  },
  {
    severity: 'P3',
    title: 'A connector token expires in three days',
    alertKind: 'token_expiring',
    alertKindLabel: 'Token expiring',
    explanation: 'The calendar connector will need a new token before Thursday.',
    dedupeKey: 'token:graph-calendar:expiry',
  },
  {
    severity: 'P2',
    title: "Today's cost is above 70 percent of the ceiling",
    alertKind: 'cost_warning',
    alertKindLabel: 'Cost warning',
    explanation: 'Agents have used most of the daily ceiling before midday.',
    dedupeKey: 'cost:daily:70',
  },
  {
    severity: 'P3',
    title: 'The calendar sync lagged for ten minutes',
    alertKind: 'sync_lag',
    alertKindLabel: 'Sync lag',
    explanation: 'The calendar sync caught up without losing any events.',
    dedupeKey: 'watcher:graph-calendar:lag',
  },
] as const;

interface Counts {
  proposals: number;
  by: number;
  to: number;
  tasks: number;
  alerts: number;
  confirm: number;
}

const COUNTS: Record<'normal' | 'overloaded', Counts> = {
  normal: { proposals: 5, by: 4, to: 3, tasks: 5, alerts: 1, confirm: 2 },
  overloaded: { proposals: 9, by: 8, to: 7, tasks: 14, alerts: 4, confirm: 3 },
};

export interface ScenarioWorld {
  records: ItemRecord[];
  agents: Agent[];
  settings: Settings;
  median: number;
  inExternalMeeting: boolean;
  minClientVersion: string;
  timeZone: string;
}

export function worldFor(scenario: Scenario, now: Date): ScenarioWorld {
  const at: Offset = (hours) => new Date(now.getTime() + hours * HOUR_MS);
  const proposals = proposalPool(at);
  const by = commitmentByPool(at);
  const to = commitmentToPool(at);
  const confirm = toConfirmPool(at);

  const records: ItemRecord[] = [];
  const addProposal = (n: number): void => {
    const spec = proposals[n];
    if (spec) records.push(proposalRecord(itemId('prop', n + 1), spec));
  };
  const addBy = (n: number): void => {
    const spec = by[n];
    if (spec) records.push(commitmentRecord(itemId('cmt', n + 1), spec));
  };
  const addTo = (n: number): void => {
    const spec = to[n];
    if (spec) records.push(commitmentRecord(itemId('cmt', 101 + n), spec));
  };
  const addConfirm = (n: number): void => {
    const spec = confirm[n];
    if (spec) records.push(commitmentRecord(itemId('cmt', 201 + n), spec));
  };
  const addTask = (n: number, working = false): void => {
    const entry = TASK_POOL[n];
    if (!entry) return;
    records.push(
      taskRecord(itemId(`task_${entry.source}`, n + 1), {
        title: entry.title,
        unit: entry.unit,
        dueAt: entry.dueHours === null ? null : at(entry.dueHours),
        source: entry.source,
        status: entry.status,
        project: entry.project,
        working,
      }),
    );
  };
  const addAlert = (n: number): void => {
    const spec = ALERT_POOL[n];
    if (spec) {
      records.push(alertRecord(itemId('alrt', n + 1), { ...spec, raisedAt: at(-1 - n) }));
    }
  };
  const range = (count: number): number[] => Array.from({ length: count }, (_, i) => i);

  if (scenario === 'quiet') {
    addProposal(3);
    addBy(0);
    addTask(2);
  } else {
    const counts = scenario === 'overloaded' ? COUNTS.overloaded : COUNTS.normal;
    range(counts.proposals).forEach(addProposal);
    range(counts.by).forEach(addBy);
    range(counts.to).forEach(addTo);
    range(counts.tasks).forEach((n) => {
      addTask(n, scenario !== 'overloaded' && scenario !== 'incident' && n === 0);
    });
    range(counts.alerts).forEach(addAlert);
    range(counts.confirm).forEach(addConfirm);
  }
  if (scenario === 'incident') {
    records.push(
      alertRecord(itemId('alrt', 90), {
        severity: 'P0',
        title: 'The kill switch is on',
        alertKind: 'kill_switch',
        alertKindLabel: 'Kill switch',
        explanation: 'An administrator paused every agent. Nothing will run until it is cleared.',
        raisedAt: at(-0.25),
        dedupeKey: 'system:kill-switch',
      }),
    );
  }

  const incident = scenario === 'incident';
  const scale = scenario === 'quiet' ? 0.2 : scenario === 'overloaded' ? 2.6 : 1;
  const working = records.some((record) => record.working);
  const agent = (
    id: string,
    name: string,
    kind: Agent['kind'],
    cost: number,
    overrides: Partial<Agent> = {},
  ): Agent => ({
    id,
    name,
    kind,
    state: incident ? 'paused' : 'idle',
    lastRunAt: at(-0.05).toISOString(),
    nextRunAt: incident ? null : at(0.1).toISOString(),
    costTodayGbp: Math.round(cost * scale * 100) / 100,
    ceilingFraction: Math.round(((cost * scale) / 15) * 1000) / 1000,
    // The kill switch overrides the principal's own scope.
    pausable: !incident,
    ...overrides,
  });
  const agents: Agent[] = [
    agent('agent_mail_watcher', 'Mail watcher', 'watcher', 0.42, {
      breaker: incident ? 'open' : 'closed',
    }),
    agent('agent_calendar_watcher', 'Calendar watcher', 'watcher', 0.18, { breaker: 'closed' }),
    agent('agent_transcript_watcher', 'Transcript watcher', 'watcher', 0.64, {
      breaker: 'closed',
      ...(scenario === 'overloaded' ? { state: 'failed' as const } : {}),
    }),
    agent('agent_drafting', 'Drafting agent', 'agent', 1.35, {
      ...(working && !incident ? { state: 'running' as const } : {}),
    }),
    agent('agent_triage', 'Triage agent', 'agent', 0.9),
    agent('job_nightly_median', 'Nightly median job', 'job', 0.05, {
      pausable: false,
      state: 'idle',
      nextRunAt: at(17).toISOString(),
    }),
  ];
  if (incident) {
    const mail = agents[0];
    if (mail) mail.state = 'breaker_open';
  }

  const settings: Settings = {
    quietHours: { start: '19:00', end: '07:00' },
    pushBudgetPerHour: 3,
    mode: 'dry_run',
    liveEligible: scenario === 'quiet',
    liveOpensAt: scenario === 'quiet' ? null : at(24 * 7).toISOString(),
    paused: false,
    pausedReason: null,
    timeZone: TIME_ZONE,
    costCeilingGbp: 15,
    global: {
      paused: incident,
      pausedReason: incident ? 'An administrator turned the kill switch on.' : null,
      mode: 'dry_run',
    },
  };

  return {
    records,
    agents,
    settings,
    median: scenario === 'quiet' ? 12 : 14,
    inExternalMeeting: scenario === 'external-meeting',
    minClientVersion:
      scenario === 'stale-client' ? STALE_MIN_CLIENT_VERSION : DEFAULT_MIN_CLIENT_VERSION,
    timeZone: TIME_ZONE,
  };
}
