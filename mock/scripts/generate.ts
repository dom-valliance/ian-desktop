// Regenerates src/generated from the contract. Output must be byte for byte
// stable so CI can fail on drift (`pnpm generate`, then `git diff --exit-code`).
import { createClient } from '@hey-api/openapi-ts';
import { fileURLToPath } from 'node:url';

const mockRoot = fileURLToPath(new URL('..', import.meta.url));

await createClient({
  input: fileURLToPath(new URL('../../contract/ian-desktop.v1.yaml', import.meta.url)),
  output: { path: `${mockRoot}src/generated`, clean: true },
  plugins: ['zod'],
});
