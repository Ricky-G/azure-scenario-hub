'use strict';

const fs = require('fs');
const http = require('http');
const path = require('path');
const { randomUUID } = require('crypto');

const port = Number(process.env.PORT || 8080);
const publicRoot = path.join(__dirname, 'public');
const contentTypes = {
  '.css': 'text/css; charset=utf-8',
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
};

function writeJson(response, statusCode, value) {
  response.writeHead(statusCode, {
    'Cache-Control': 'no-store',
    'Content-Type': 'application/json; charset=utf-8',
  });
  response.end(JSON.stringify(value));
}

async function getControlPlaneEvidence() {
  const apimResourceId = process.env.APIM_RESOURCE_ID || '';
  const gatewayName = process.env.SELF_HOSTED_GATEWAY_NAME || '';
  const identityEndpoint = process.env.IDENTITY_ENDPOINT;
  const identityHeader = process.env.IDENTITY_HEADER;

  if (!apimResourceId || !gatewayName || !identityEndpoint || !identityHeader) {
    return {
      verified: false,
      gatewayName,
      reason: 'Managed identity or APIM configuration is unavailable.',
    };
  }

  try {
    const tokenUrl = new URL(identityEndpoint);
    tokenUrl.searchParams.set('api-version', '2019-08-01');
    tokenUrl.searchParams.set('resource', 'https://management.azure.com/');
    const tokenResponse = await fetch(tokenUrl, {
      headers: { 'X-IDENTITY-HEADER': identityHeader },
      signal: AbortSignal.timeout(10000),
    });
    if (!tokenResponse.ok) {
      throw new Error(`Managed identity token request returned ${tokenResponse.status}.`);
    }
    const token = await tokenResponse.json();
    const armHeaders = { Authorization: `Bearer ${token.access_token}` };
    const gatewayUrl = `https://management.azure.com${apimResourceId}/gateways/${gatewayName}?api-version=2024-05-01`;
    const associationsUrl = `https://management.azure.com${apimResourceId}/gateways/${gatewayName}/apis?api-version=2024-05-01`;
    const [gatewayResponse, associationsResponse] = await Promise.all([
      fetch(gatewayUrl, { headers: armHeaders, signal: AbortSignal.timeout(10000) }),
      fetch(associationsUrl, { headers: armHeaders, signal: AbortSignal.timeout(10000) }),
    ]);
    if (!gatewayResponse.ok || !associationsResponse.ok) {
      throw new Error(`APIM control-plane requests returned ${gatewayResponse.status}/${associationsResponse.status}.`);
    }
    const gateway = await gatewayResponse.json();
    const associations = await associationsResponse.json();
    const apiNames = (associations.value || []).map((api) => api.name);
    return {
      verified: gateway.name === gatewayName && apiNames.includes('dr-api'),
      apimServiceName: process.env.APIM_SERVICE_NAME || '',
      gatewayName: gateway.name,
      gatewayLocation: gateway.properties?.locationData?.name || '',
      associatedApis: apiNames,
    };
  } catch (error) {
    return {
      verified: false,
      gatewayName,
      reason: error instanceof Error ? error.message : String(error),
    };
  }
}

function buildHopEvidence(route, headers, body, requestId, controlPlane) {
  const frontDoorReference = headers.get('x-azure-ref') || '';
  const appGatewayMarker = headers.get('x-appgateway-hop') || '';
  const apimGateway = headers.get('x-apim-gateway') || '';
  const apimRoute = headers.get('x-scenario-route') || '';
  const apimService = headers.get('x-apim-service') || '';
  const backendService = headers.get('x-backend-service') || '';
  const backendRequestId = headers.get('x-backend-request-id') || body?.requestId || '';

  if (route === 'happy') {
    return [
      {
        id: 'front-door',
        verified: Boolean(frontDoorReference),
        proof: frontDoorReference || 'No Azure Front Door reference header returned.',
      },
      {
        id: 'app-gateway',
        verified: appGatewayMarker === 'private-waf-v2',
        proof: appGatewayMarker || 'Application Gateway marker missing.',
      },
      {
        id: 'managed-apim',
        verified: apimGateway === 'managed'
          && apimRoute === 'happy-managed'
          && apimService === `${process.env.APIM_SERVICE_NAME}.azure-api.net`,
        proof: `${apimService || 'APIM'} | gateway=${apimGateway || 'missing'} | route=${apimRoute || 'missing'}`,
      },
      {
        id: 'backend',
        verified: backendService === 'mock-onprem-aks' && backendRequestId === requestId,
        proof: `${backendService || 'Backend marker missing'} | request=${backendRequestId || 'not echoed'}`,
      },
    ];
  }

  return [
    {
      id: 'front-door',
      verified: Boolean(frontDoorReference),
      proof: frontDoorReference || 'No Azure Front Door reference header returned.',
    },
    {
      id: 'aks-ingress',
      verified: apimGateway === 'self-hosted',
      proof: apimGateway === 'self-hosted'
        ? `${process.env.DR_ORIGIN_HOSTNAME || 'AKS origin'} accepted the Front Door request.`
        : 'No response arrived from the AKS-hosted gateway origin.',
    },
    {
      id: 'self-hosted-gateway',
      verified: apimGateway === 'self-hosted'
        && apimRoute === 'dr-self-hosted'
        && apimService === process.env.APIM_SERVICE_NAME
        && controlPlane.verified,
      proof: controlPlane.verified
        ? `${controlPlane.gatewayName} registered to ${controlPlane.apimServiceName}; APIs: ${controlPlane.associatedApis.join(', ')}`
        : controlPlane.reason || 'APIM gateway registration could not be verified.',
    },
    {
      id: 'backend',
      verified: backendService === 'mock-onprem-aks' && backendRequestId === requestId,
      proof: `${backendService || 'Backend marker missing'} | request=${backendRequestId || 'not echoed'}`,
    },
  ];
}

async function runPathTest(route) {
  const frontDoorHostname = process.env.FRONT_DOOR_HOSTNAME || '';
  if (!frontDoorHostname) {
    throw new Error('FRONT_DOOR_HOSTNAME is not configured.');
  }

  const requestId = randomUUID();
  const url = `https://${frontDoorHostname}/${route}/hello`;
  const started = performance.now();
  const controlPlanePromise = route === 'dr'
    ? getControlPlaneEvidence()
    : Promise.resolve({ verified: true });
  const upstream = await fetch(url, {
    cache: 'no-store',
    headers: {
      'Cache-Control': 'no-cache',
      'X-Scenario-Request-Id': requestId,
    },
    signal: AbortSignal.timeout(35000),
  });
  const rawBody = await upstream.text();
  let body = rawBody;
  try {
    body = JSON.parse(rawBody);
  } catch {
    // Preserve intermediary HTML/text errors as evidence.
  }
  const controlPlane = await controlPlanePromise;
  const hops = buildHopEvidence(route, upstream.headers, body, requestId, controlPlane);
  const allHopsVerified = hops.every((hop) => hop.verified);

  return {
    ok: upstream.ok && allHopsVerified,
    route,
    requestId,
    url,
    status: upstream.status,
    latencyMs: Math.round(performance.now() - started),
    hops,
    controlPlane: route === 'dr' ? controlPlane : undefined,
    response: {
      body,
      headers: {
        azureReference: upstream.headers.get('x-azure-ref') || '',
        appGatewayHop: upstream.headers.get('x-appgateway-hop') || '',
        apimGateway: upstream.headers.get('x-apim-gateway') || '',
        apimRoute: upstream.headers.get('x-scenario-route') || '',
        apimService: upstream.headers.get('x-apim-service') || '',
        apimRequestId: upstream.headers.get('x-ms-request-id') || '',
        backendService: upstream.headers.get('x-backend-service') || '',
        backendRequestId: upstream.headers.get('x-backend-request-id') || '',
      },
    },
  };
}

const server = http.createServer(async (request, response) => {
  const requestUrl = new URL(request.url, `http://${request.headers.host || 'localhost'}`);

  if (requestUrl.pathname === '/config') {
    writeJson(response, 200, {
      frontDoorHostname: process.env.FRONT_DOOR_HOSTNAME || '',
      apimServiceName: process.env.APIM_SERVICE_NAME || '',
      selfHostedGatewayName: process.env.SELF_HOSTED_GATEWAY_NAME || '',
      drOriginHostname: process.env.DR_ORIGIN_HOSTNAME || '',
    });
    return;
  }

  if (requestUrl.pathname === '/api/test') {
    const route = requestUrl.searchParams.get('route');
    if (!['happy', 'dr'].includes(route)) {
      writeJson(response, 400, { ok: false, error: 'Route must be happy or dr.' });
      return;
    }
    try {
      const result = await runPathTest(route);
      writeJson(response, result.ok ? 200 : 502, result);
    } catch (error) {
      writeJson(response, 502, {
        ok: false,
        route,
        error: error instanceof Error ? error.message : String(error),
      });
    }
    return;
  }

  const relativePath = requestUrl.pathname === '/'
    ? 'index.html'
    : decodeURIComponent(requestUrl.pathname).replace(/^\/+/, '');
  const filePath = path.resolve(publicRoot, relativePath);
  const allowedPath = filePath === path.join(publicRoot, 'index.html') || filePath.startsWith(`${publicRoot}${path.sep}`);

  if (!allowedPath) {
    response.writeHead(403).end('Forbidden');
    return;
  }

  fs.readFile(filePath, (error, content) => {
    if (error) {
      response.writeHead(error.code === 'ENOENT' ? 404 : 500).end(error.code === 'ENOENT' ? 'Not found' : 'Server error');
      return;
    }

    response.writeHead(200, {
      'Cache-Control': 'no-store',
      'Content-Type': contentTypes[path.extname(filePath)] || 'application/octet-stream',
    });
    response.end(content);
  });
});

server.listen(port, () => {
  console.log(`Path tester listening on port ${port}`);
});