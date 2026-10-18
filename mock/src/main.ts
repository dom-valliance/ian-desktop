import { loadConfig } from './config.js';
import { buildMockServer } from './http/app.js';

const config = loadConfig(process.env);
const { app } = buildMockServer({
  ...(config.MOCK_START_AT === undefined ? {} : { startAt: new Date(config.MOCK_START_AT) }),
  scenario: config.MOCK_SCENARIO,
  heartbeatIntervalMs: config.MOCK_HEARTBEAT_INTERVAL_MS,
  actionDelayMs: config.MOCK_ACTION_DELAY_MS,
  logLevel: config.LOG_LEVEL,
});

await app.listen({ host: config.MOCK_HOST, port: config.MOCK_PORT });
process.stdout.write(
  `Mock listening on http://${config.MOCK_HOST}:${String(config.MOCK_PORT)}/desktop/v1 (scenario ${config.MOCK_SCENARIO})\n`,
);

for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.on(signal, () => {
    void app.close().then(() => process.exit(0));
  });
}
