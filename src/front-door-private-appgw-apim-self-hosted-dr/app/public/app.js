'use strict';

const routeButtons = [...document.querySelectorAll('[data-route]')];
const runButton = document.querySelector('#run-test');
const routeTitle = document.querySelector('#route-title');
const routeState = document.querySelector('#route-state');
const happyFlow = document.querySelector('#happy-flow');
const drFlow = document.querySelector('#dr-flow');
const statusCode = document.querySelector('#status-code');
const gatewayName = document.querySelector('#gateway-name');
const latency = document.querySelector('#latency');
const requestId = document.querySelector('#request-id');
const requestUrl = document.querySelector('#request-url');
const responseBody = document.querySelector('#response-body');

let selectedRoute = 'happy';

function activeFlow() {
  return selectedRoute === 'happy' ? happyFlow : drFlow;
}

function resetEvidence() {
  [happyFlow, drFlow].forEach((flow) => {
    flow.querySelectorAll('li').forEach((hop) => {
      hop.className = '';
      hop.querySelector('.hop-status').textContent = 'Not tested';
      hop.querySelector('.hop-proof').textContent = 'No request evidence yet';
    });
  });
  statusCode.textContent = '-';
  gatewayName.textContent = '-';
  latency.textContent = '-';
  requestId.textContent = '-';
  requestUrl.textContent = 'Not run';
  responseBody.textContent = 'Choose a route and run the test.';
}

function markFlowRunning() {
  activeFlow().querySelectorAll('li').forEach((hop) => {
    hop.className = 'checking';
    hop.querySelector('.hop-status').textContent = 'Checking';
    hop.querySelector('.hop-proof').textContent = 'Awaiting correlated evidence';
  });
}

function renderHops(hops = []) {
  const evidenceById = new Map(hops.map((hop) => [hop.id, hop]));
  activeFlow().querySelectorAll('li').forEach((element) => {
    const evidence = evidenceById.get(element.dataset.hop);
    const verified = Boolean(evidence?.verified);
    element.className = verified ? 'verified' : 'failed';
    element.querySelector('.hop-status').textContent = verified ? 'Verified' : 'Failed';
    element.querySelector('.hop-proof').textContent = evidence?.proof || 'No proof returned for this hop';
  });
}

function setRoute(route) {
  selectedRoute = route;
  routeButtons.forEach((button) => {
    const active = button.dataset.route === route;
    button.classList.toggle('active', active);
    button.setAttribute('aria-pressed', String(active));
  });
  happyFlow.classList.toggle('hidden', route !== 'happy');
  drFlow.classList.toggle('hidden', route !== 'dr');
  routeTitle.textContent = route === 'happy' ? 'Managed Azure path' : 'Mock on-premises DR path';
  routeState.className = 'state idle';
  routeState.textContent = 'Ready';
  resetEvidence();
}

async function runTest() {
  runButton.disabled = true;
  routeState.className = 'state running';
  routeState.textContent = 'Running';
  resetEvidence();
  markFlowRunning();
  responseBody.textContent = 'Collecting edge, gateway, control-plane, and backend evidence...';

  try {
    const response = await fetch(`/api/test?route=${selectedRoute}`, { cache: 'no-store' });
    const result = await response.json();
    renderHops(result.hops);
    statusCode.textContent = result.status ? String(result.status) : 'Error';
    gatewayName.textContent = result.response?.headers?.apimGateway || 'not reached';
    latency.textContent = Number.isFinite(result.latencyMs) ? `${result.latencyMs} ms` : '-';
    requestId.textContent = result.requestId || '-';
    requestUrl.textContent = result.url || 'Request did not start';
    responseBody.textContent = JSON.stringify(result, null, 2);

    const passed = Boolean(result.ok);
    routeState.className = `state ${passed ? 'passed' : 'failed'}`;
    routeState.textContent = passed ? 'All hops verified' : 'Evidence incomplete';
  } catch (error) {
    responseBody.textContent = error instanceof Error ? error.message : String(error);
    activeFlow().querySelectorAll('li').forEach((hop) => {
      hop.className = 'failed';
      hop.querySelector('.hop-status').textContent = 'Failed';
      hop.querySelector('.hop-proof').textContent = 'Evidence service request failed';
    });
    routeState.className = 'state failed';
    routeState.textContent = 'Request failed';
  } finally {
    runButton.disabled = false;
  }
}

routeButtons.forEach((button) => button.addEventListener('click', () => setRoute(button.dataset.route)));
runButton.addEventListener('click', runTest);