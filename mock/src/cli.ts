import { USAGE, UsageError, parseCommand } from './cliCommand.js';

const base = process.env.MOCK_URL ?? 'http://127.0.0.1:4317';

function fail(message: string): never {
  process.stderr.write(`${message}\n`);
  process.exit(1);
}

let request;
try {
  request = parseCommand(process.argv.slice(2));
} catch (error) {
  if (error instanceof UsageError) fail(`${error.message}\n\n${USAGE}`);
  throw error;
}

let response: Response;
try {
  response = await fetch(`${base}${request.path}`, {
    method: request.method,
    ...(request.body === undefined
      ? {}
      : { headers: { 'content-type': 'application/json' }, body: JSON.stringify(request.body) }),
  });
} catch {
  fail(`Cannot reach the mock at ${base}. Start it with "pnpm --dir mock dev" or scripts/dev.sh.`);
}

const text = await response.text();
if (!response.ok) fail(`The mock answered ${String(response.status)}: ${text}`);
process.stdout.write(`${text}\n`);
