const PARTS = ['year', 'month', 'day', 'hour', 'minute', 'second'] as const;

function localFields(date: Date, timeZone: string): Record<(typeof PARTS)[number], number> {
  const formatter = new Intl.DateTimeFormat('en-GB', {
    timeZone,
    hourCycle: 'h23',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  });
  const fields: Record<string, number> = {};
  for (const part of formatter.formatToParts(date)) {
    if ((PARTS as readonly string[]).includes(part.type)) fields[part.type] = Number(part.value);
  }
  return {
    year: fields.year ?? 0,
    month: fields.month ?? 1,
    day: fields.day ?? 1,
    hour: fields.hour ?? 0,
    minute: fields.minute ?? 0,
    second: fields.second ?? 0,
  };
}

/** The zone's offset from UTC at this instant, in milliseconds. */
function offsetMs(date: Date, timeZone: string): number {
  const f = localFields(date, timeZone);
  const wallAsUtc = Date.UTC(f.year, f.month - 1, f.day, f.hour, f.minute, f.second);
  return wallAsUtc - Math.floor(date.getTime() / 1000) * 1000;
}

/** The first instant of the next local day in the zone. */
export function endOfLocalDay(date: Date, timeZone: string): Date {
  const f = localFields(date, timeZone);
  return new Date(Date.UTC(f.year, f.month - 1, f.day + 1, 0, 0, 0) - offsetMs(date, timeZone));
}

export function isSameLocalDay(a: Date, b: Date, timeZone: string): boolean {
  return endOfLocalDay(a, timeZone).getTime() === endOfLocalDay(b, timeZone).getTime();
}

export function formatClock(date: Date, timeZone: string): string {
  const f = localFields(date, timeZone);
  return `${String(f.hour).padStart(2, '0')}:${String(f.minute).padStart(2, '0')}`;
}

export function formatWeekday(date: Date, timeZone: string): string {
  return new Intl.DateTimeFormat('en-GB', { timeZone, weekday: 'long' }).format(date);
}

export function formatDayMonth(date: Date, timeZone: string): string {
  return new Intl.DateTimeFormat('en-GB', { timeZone, day: 'numeric', month: 'long' }).format(date);
}

function minutesOfDay(date: Date, timeZone: string): number {
  const f = localFields(date, timeZone);
  return f.hour * 60 + f.minute;
}

function parseHhMm(value: string): number {
  const [hours, minutes] = value.split(':').map(Number);
  return (hours ?? 0) * 60 + (minutes ?? 0);
}

/** Whether `date` falls inside a daily window in the zone; the window may cross midnight. */
export function isWithinQuietHours(
  date: Date,
  timeZone: string,
  quietHours: { start: string; end: string },
): boolean {
  const now = minutesOfDay(date, timeZone);
  const start = parseHhMm(quietHours.start);
  const end = parseHhMm(quietHours.end);
  if (start === end) return false;
  return start < end ? now >= start && now < end : now >= start || now < end;
}

export const MINUTE_MS = 60_000;
export const HOUR_MS = 60 * MINUTE_MS;
export const DAY_MS = 24 * HOUR_MS;
