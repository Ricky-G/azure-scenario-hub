// k6 script — APIM-A (shared backend + rewrite-uri pattern)
// Run: k6 run -e APIM_A_URL=https://<apim-a>.azure-api.net apim-a-shared.js
import { options as commonOptions, buildIteration } from './common.js';

export const options = commonOptions;

const BASE = __ENV.APIM_A_URL;
if (!BASE) { throw new Error('APIM_A_URL env var is required'); }

export const iter = buildIteration(BASE, 'A');
