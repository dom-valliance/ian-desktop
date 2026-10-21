import type { MockClock } from './clock.js';
import { DAY_MS } from './time.js';
import type { StreamEvent } from './types.js';

export interface StoredEvent {
  /** Absent only for transient events, which are never stored (`heartbeat`). */
  id: number | null;
  event: StreamEvent;
}

export const REPLAY_WINDOW_MS = DAY_MS;

/**
 * One principal's event log. Ids rise by one, 24 hours of events are replayable by the mock clock,
 * and a `Last-Event-ID` the log cannot honour is refused (ADR 0009, decision 10).
 */
export class EventLog {
  private readonly events: { id: number; at: Date; event: StreamEvent }[] = [];
  private lastId: number;
  /** The highest id that has aged out. A client holding less than this has missed events. */
  private prunedThrough: number;
  private readonly subscribers = new Set<(stored: StoredEvent) => void>();

  /**
   * Ids start at the wall clock in milliseconds, so an id from an earlier process is below this
   * one's window and answers 410 instead of replaying the wrong history.
   */
  constructor(
    private readonly clock: MockClock,
    firstEventId: number = Date.now(),
  ) {
    this.lastId = firstEventId;
    this.prunedThrough = firstEventId;
  }

  latestId(): number {
    return this.lastId;
  }

  append(event: StreamEvent): number {
    this.lastId += 1;
    this.events.push({ id: this.lastId, at: this.clock.now(), event });
    this.deliver({ id: this.lastId, event });
    return this.lastId;
  }

  /** Delivers to open streams without storing or numbering the event. */
  publishTransient(event: StreamEvent): void {
    this.deliver({ id: null, event });
  }

  /** The events after `lastEventId`, or `null` when the log does not hold that id. */
  replayAfter(lastEventId: number): StoredEvent[] | null {
    this.prune();
    if (lastEventId < this.prunedThrough || lastEventId > this.lastId) return null;
    return this.events
      .filter((stored) => stored.id > lastEventId)
      .map((stored) => ({ id: stored.id, event: stored.event }));
  }

  subscribe(listener: (stored: StoredEvent) => void): () => void {
    this.subscribers.add(listener);
    return () => {
      this.subscribers.delete(listener);
    };
  }

  /** Ages out by each event's own time, since a clock set back leaves later events dated ahead. */
  private prune(): void {
    const cutoff = this.clock.now().getTime() - REPLAY_WINDOW_MS;
    for (let index = this.events.length - 1; index >= 0; index -= 1) {
      const stored = this.events[index];
      if (stored && stored.at.getTime() < cutoff) {
        this.events.splice(index, 1);
        this.prunedThrough = Math.max(this.prunedThrough, stored.id);
      }
    }
  }

  private deliver(stored: StoredEvent): void {
    this.prune();
    for (const listener of this.subscribers) listener(stored);
  }
}
