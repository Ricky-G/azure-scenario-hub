// Shared k6 configuration for both APIM-A and APIM-B runs.
// Identical scenarios + RNG seed ensure a fair comparison.
import http from 'k6/http';
import { check } from 'k6';

export const options = {
    // Discardable warm-up + 3-stage step load.
    scenarios: {
        warmup: {
            executor: 'constant-vus',
            vus: 10,
            duration: '30s',
            tags: { stage: 'warmup' },
            exec: 'iter',
            gracefulStop: '5s',
        },
        stage_50: {
            executor: 'constant-vus',
            vus: 50,
            duration: '5m',
            startTime: '35s',
            tags: { stage: '50vu' },
            exec: 'iter',
            gracefulStop: '10s',
        },
        stage_100: {
            executor: 'constant-vus',
            vus: 100,
            duration: '5m',
            startTime: '5m45s',
            tags: { stage: '100vu' },
            exec: 'iter',
            gracefulStop: '10s',
        },
        stage_200: {
            executor: 'constant-vus',
            vus: 200,
            duration: '5m',
            startTime: '10m55s',
            tags: { stage: '200vu' },
            exec: 'iter',
            gracefulStop: '10s',
        },
    },
    thresholds: {
        // Soft thresholds — informational only; report builder applies real verdict.
        'http_req_failed': ['rate<0.05'],
    },
    discardResponseBodies: true,
};

// Round-robin all 10 APIs per VU iteration.
export function buildIteration(baseUrl, apimTag) {
    return function iter() {
        // Deterministic per-VU ordering via __VU and __ITER for reproducibility.
        const apiIndex = ((__VU + __ITER) % 10) + 1;
        const svc = 'svc' + String(apiIndex).padStart(2, '0');
        const resourceId = (__ITER % 1000) + 1;
        const url = `${baseUrl}/${svc}/v1/resource/${resourceId}`;
        const res = http.get(url, {
            tags: { apim: apimTag, api: svc },
        });
        check(res, { 'status is 200': (r) => r.status === 200 });
    };
}
