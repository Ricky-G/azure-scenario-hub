// k6 script — APIM-B (one-backend-per-API pattern)
// Run: k6 run -e APIM_B_URL=https://<apim-b>.azure-api.net apim-b-perapi.js
import { options as commonOptions, buildIteration } from './common.js';

export const options = commonOptions;

const BASE = __ENV.APIM_B_URL;
if (!BASE) { throw new Error('APIM_B_URL env var is required'); }

export const iter = buildIteration(BASE, 'B');
