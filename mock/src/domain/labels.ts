import {
  endOfLocalDay,
  formatClock,
  formatDayMonth,
  formatWeekday,
  isSameLocalDay,
} from './time.js';
import type { ItemRecord } from './types.js';

export function dueText(dueAt: Date | null, now: Date, timeZone: string): string {
  if (dueAt === null) return 'no due date';
  if (dueAt.getTime() < now.getTime()) return 'overdue';
  if (isSameLocalDay(dueAt, now, timeZone)) return `due today at ${formatClock(dueAt, timeZone)}`;
  const tomorrow = endOfLocalDay(now, timeZone);
  if (dueAt.getTime() < tomorrow.getTime() + 24 * 3_600_000) return 'due tomorrow';
  if (dueAt.getTime() < now.getTime() + 7 * 24 * 3_600_000) {
    return `due ${formatWeekday(dueAt, timeZone)}`;
  }
  return `due ${formatDayMonth(dueAt, timeZone)}`;
}

/** The one-line meta text: the fixed part of the record plus whatever depends on the clock. */
export function metaLine(record: ItemRecord, now: Date, timeZone: string): string {
  const { detail } = record;
  switch (detail.kind) {
    case 'proposal': {
      const expiresAt = new Date(detail.expiresAt);
      const when = isSameLocalDay(expiresAt, now, timeZone)
        ? `at ${formatClock(expiresAt, timeZone)}`
        : dueText(expiresAt, now, timeZone).replace(/^due /, '');
      return `${record.metaBase}, expires ${when}`;
    }
    case 'alert':
      return `${record.severity ?? 'P3'}, raised at ${formatClock(new Date(detail.raisedAt), timeZone)}`;
    case 'task':
      return `${record.metaBase}, ${dueText(record.dueAt, now, timeZone)}`;
    case 'commitment_by':
    case 'commitment_to':
      return `${record.metaBase}, ${dueText(record.dueAt, now, timeZone)}`;
  }
}
