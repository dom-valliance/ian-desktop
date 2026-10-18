/** Mock time. It stands still until a request moves it, so every derived value is repeatable. */
export class MockClock {
  private current: Date;

  constructor(start: Date) {
    this.current = new Date(start.getTime());
  }

  now(): Date {
    return new Date(this.current.getTime());
  }

  set(to: Date): void {
    this.current = new Date(to.getTime());
  }

  advance(ms: number): void {
    this.current = new Date(this.current.getTime() + ms);
  }
}
