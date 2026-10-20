import { describe, expect, it } from 'vitest';
import {
  attentionOf,
  buildToday,
  buildViews,
  horizonOf,
  pressureOf,
  renderItem,
} from '../domain/derive.js';
import { alertRecord, commitmentRecord, proposalRecord, taskRecord } from '../domain/factories.js';
import { worldFor } from '../domain/seeds.js';
import { HOUR_MS, MINUTE_MS } from '../domain/time.js';
import type { Item, ItemRecord } from '../domain/types.js';
import { START } from './harness.js';

const TZ = 'Europe/London';
const NOW = START;
const at = (hours: number): Date => new Date(NOW.getTime() + hours * HOUR_MS);
const unit = { id: 'unit_x', name: '[CLIENT X]' };

const commitment = (hours: number | null, toConfirm = false): ItemRecord =>
  commitmentRecord('cmt_1', {
    direction: 'commitment_by',
    title: 'Send [PERSON A] a document',
    counterparty: { id: 'person_1', name: '[PERSON A]' },
    unit,
    dueAt: hours === null ? null : at(hours),
    quote: 'I will send it.',
    source: { kind: 'email', system: 'graph', label: 'Email', observedAt: at(-2) },
    toConfirm,
  });

const proposal = (expiresInMinutes: number): ItemRecord =>
  proposalRecord('prop_1', {
    title: 'Send a reply',
    summary: 'A short reply.',
    actionClass: 'draft_email',
    actionClassLabel: 'Draft email',
    targetSystem: 'graph',
    targetSystemLabel: 'Outlook',
    unit,
    expiresAt: new Date(NOW.getTime() + expiresInMinutes * MINUTE_MS),
  });

const alert = (severity: 'P0' | 'P1' | 'P2' | 'P3'): ItemRecord =>
  alertRecord('alrt_1', {
    severity,
    title: 'An alert',
    alertKind: 'mock',
    alertKindLabel: 'Mock',
    explanation: 'Invented.',
    raisedAt: at(-1),
    dedupeKey: 'k',
  });

const task = (hours: number | null): ItemRecord =>
  taskRecord('task_notion_1', {
    title: 'Write a note',
    unit,
    dueAt: hours === null ? null : at(hours),
    source: 'notion',
    status: 'Not started',
    project: null,
  });

describe('horizon (spec 5.4)', () => {
  it.each([
    ['due later today', commitment(3), 'now'],
    ['overdue', commitment(-5), 'now'],
    ['P1 alert', alert('P1'), 'now'],
    ['P0 alert', alert('P0'), 'now'],
    ['P2 alert', alert('P2'), 'later'],
    ['proposal expiring today', proposal(120), 'now'],
    ['proposal expiring in three days', proposal(3 * 24 * 60), 'week'],
    ['due in three days', commitment(72), 'week'],
    ['due in eight days', commitment(192), 'later'],
    ['task with no due date', task(null), 'later'],
  ] as const)('puts %s in %s', (_name, record, expected) => {
    expect(horizonOf(record, NOW, TZ)).toBe(expected);
  });
});

describe('attention (spec 6.6)', () => {
  it.each([
    ['P0 alert', alert('P0'), 'stop'],
    ['P1 alert', alert('P1'), 'urgent'],
    ['P2 alert', alert('P2'), 'needs_you'],
    ['P3 alert', alert('P3'), 'ambient'],
    ['proposal expiring in 10 minutes', proposal(10), 'urgent'],
    ['proposal expiring in 15 minutes', proposal(15), 'urgent'],
    ['proposal expiring in 20 minutes', proposal(20), 'needs_you'],
    ['commitment due today', commitment(3), 'needs_you'],
    ['commitment due in three days', commitment(72), 'ambient'],
    ['commitment awaiting confirmation', commitment(3, true), 'ambient'],
    ['task due today', task(3), 'ambient'],
  ] as const)('puts %s on %s', (_name, record, expected) => {
    expect(attentionOf(record, NOW, TZ)).toBe(expected);
  });

  it('puts an item with risk language on the urgent rung', () => {
    const record = { ...commitment(72), riskLanguage: true };
    expect(attentionOf(record, NOW, TZ)).toBe('urgent');
  });
});

describe('pressure', () => {
  it('stays between 0 and 1 for every seeded item in every scenario', () => {
    for (const scenario of ['quiet', 'normal', 'overloaded', 'incident'] as const) {
      for (const record of worldFor(scenario, NOW).records) {
        const pressure = pressureOf(record, NOW);
        expect(pressure).toBeGreaterThanOrEqual(0);
        expect(pressure).toBeLessThanOrEqual(1);
      }
    }
  });

  it('rises as a deadline approaches and again once it has passed', () => {
    const week = pressureOf(commitment(168), NOW);
    const day = pressureOf(commitment(24), NOW);
    const hour = pressureOf(commitment(1), NOW);
    const overdue = pressureOf(commitment(-24), NOW);
    expect(week).toBeLessThan(day);
    expect(day).toBeLessThan(hour);
    expect(hour).toBeLessThan(overdue);
  });

  it('uses the severity weight for an alert and a floor for an item with no deadline', () => {
    expect(pressureOf(alert('P0'), NOW)).toBe(1);
    expect(pressureOf(alert('P1'), NOW)).toBeGreaterThan(pressureOf(alert('P2'), NOW));
    expect(pressureOf(alert('P2'), NOW)).toBeGreaterThan(pressureOf(alert('P3'), NOW));
    expect(pressureOf(task(null), NOW)).toBe(0.1);
  });

  it('treats a proposal expiry as its deadline', () => {
    expect(pressureOf(proposal(30), NOW)).toBeGreaterThan(pressureOf(proposal(60 * 24), NOW));
  });
});

const render = (records: ItemRecord[]): Item[] =>
  records.map((record) => renderItem(record, NOW, TZ));
const context = {
  now: NOW,
  timeZone: TZ,
  median: 14,
  settings: { quietHours: { start: '19:00', end: '07:00' } },
  inExternalMeeting: false,
};

describe('the Pillars field', () => {
  it('keeps the four highest-pressure units and folds the rest into Other, last', () => {
    const items = render(worldFor('overloaded', NOW).records);
    const today = buildToday(items, context);
    expect(today.field.units).toHaveLength(5);
    expect(today.field.units.at(-1)).toEqual({ id: 'other', name: 'Other' });
    expect(
      today.field.cells.every((cell) => today.field.units.some((u) => u.id === cell.unitId)),
    ).toBe(true);
    const placed = today.field.cells.flatMap((cell) => cell.itemIds);
    expect(new Set(placed).size).toBe(today.orbit.load);
    expect(placed).toHaveLength(today.orbit.load);
  });

  it('omits Other when every item has a unit in the top four', () => {
    const items = render(worldFor('quiet', NOW).records);
    const today = buildToday(items, context);
    expect(today.field.units.some((unit) => unit.id === 'other')).toBe(false);
  });

  it('computes a cell as the union of its items pressures and takes the first item kind', () => {
    const items = render([commitment(3), { ...proposal(60), id: 'prop_2' }]);
    const today = buildToday(items, context);
    const cell = today.field.cells.find((candidate) => candidate.horizon === 'now');
    const [a, b] = items.map((item) => item.pressure);
    expect(cell?.pressure).toBeCloseTo(1 - (1 - (a ?? 0)) * (1 - (b ?? 0)), 2);
    const first = items.slice().sort((x, y) => y.pressure - x.pressure)[0];
    expect(cell?.kind).toBe(first?.kind);
  });

  it('leaves commitments awaiting confirmation out of Today but keeps them in the views', () => {
    const items = render([commitment(3), { ...commitment(5, true), id: 'cmt_2' }]);
    const today = buildToday(items, context);
    expect(today.orbit.load).toBe(1);
    expect(buildViews(items, 6).commitments.toConfirm).toEqual(['cmt_2']);
  });

  it('floors the median at 1', () => {
    const today = buildToday([], { ...context, median: 0 });
    expect(today.orbit.median).toBe(1);
  });

  it('caps the Orbit at five satellites and counts the overflow', () => {
    const records = Array.from({ length: 8 }, (_, n) => ({
      ...commitment(1 + n),
      id: `cmt_${String(n)}`,
    }));
    const today = buildToday(render(records), context);
    expect(today.orbit.itemIds).toHaveLength(5);
    expect(today.orbit.overflow).toBe(3);
    expect(today.orbit.nowCount).toBe(8);
  });
});

describe('the views', () => {
  it('groups proposals by action class with the soonest expiry first', () => {
    const early = { ...proposal(30), id: 'prop_a' };
    const late = { ...proposal(600), id: 'prop_b' };
    const other = {
      ...proposal(10),
      id: 'prop_c',
      detail: {
        ...(proposal(10).detail as object),
        actionClass: 'update_task',
        actionClassLabel: 'Update task',
      },
    } as ItemRecord;
    const views = buildViews(render([late, early, other]), 6);
    expect(views.proposals.map((group) => group.id)).toEqual(['update_task', 'draft_email']);
    expect(views.proposals[1]?.itemIds).toEqual(['prop_a', 'prop_b']);
  });

  it('puts P0 first among alerts and omits empty severities', () => {
    const views = buildViews(
      render([
        { ...alert('P2'), id: 'alrt_2' },
        { ...alert('P0'), id: 'alrt_0' },
      ]),
      6,
    );
    expect(views.alerts.map((group) => group.id)).toEqual(['P0', 'P2']);
  });

  it('pins the P0 alert group and no other', () => {
    const views = buildViews(
      render([
        { ...alert('P2'), id: 'alrt_2' },
        { ...alert('P0'), id: 'alrt_0' },
      ]),
      6,
    );
    expect(views.alerts.map((group) => group.pinned)).toEqual([true, undefined]);
  });

  it('sections tasks by horizon and then unit', () => {
    const views = buildViews(render([task(3), { ...task(null), id: 'task_notion_2' }]), 6);
    expect(views.tasks.map((section) => section.horizon)).toEqual(['now', 'later']);
    expect(views.tasks[0]?.groups[0]?.label).toBe('[CLIENT X]');
  });
});
