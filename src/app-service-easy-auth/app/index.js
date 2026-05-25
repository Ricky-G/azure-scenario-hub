// Minimal Easy Auth round-trip demo.
// Shows the full query string that arrived at this request, plus the authenticated
// user's claims that Easy Auth injects via the x-ms-client-principal header.
const express = require('express');
const app = express();
const port = process.env.PORT || 8080;

function decodePrincipal(req) {
  const header = req.header('x-ms-client-principal');
  if (!header) return null;
  try {
    const json = Buffer.from(header, 'base64').toString('utf8');
    return JSON.parse(json);
  } catch (e) {
    return { error: 'Failed to decode x-ms-client-principal', detail: String(e) };
  }
}

function esc(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function renderPage(req) {
  const fullUrl = `${req.protocol}://${req.get('host')}${req.originalUrl}`;
  const queryEntries = Object.entries(req.query);
  const principal = decodePrincipal(req);
  const userName = req.header('x-ms-client-principal-name') || '(unknown)';
  const userId = req.header('x-ms-client-principal-id') || '(unknown)';
  const idp = req.header('x-ms-client-principal-idp') || '(unknown)';

  const queryRows = queryEntries.length === 0
    ? `<tr><td colspan="2"><em>No query string parameters on this request.</em></td></tr>`
    : queryEntries
        .map(([k, v]) => `<tr><td><code>${esc(k)}</code></td><td><code>${esc(v)}</code></td></tr>`)
        .join('');

  const claimsRows = principal && Array.isArray(principal.claims)
    ? principal.claims
        .map(c => `<tr><td><code>${esc(c.typ)}</code></td><td><code>${esc(c.val)}</code></td></tr>`)
        .join('')
    : `<tr><td colspan="2"><em>No claims available.</em></td></tr>`;

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>App Service Easy Auth — Query String Round-Trip Demo</title>
  <style>
    body { font-family: -apple-system, Segoe UI, Roboto, sans-serif; max-width: 980px; margin: 2rem auto; padding: 0 1rem; color: #222; }
    h1 { color: #0078d4; }
    h2 { border-bottom: 1px solid #ddd; padding-bottom: 0.3rem; margin-top: 2rem; }
    table { border-collapse: collapse; width: 100%; margin-top: 0.5rem; }
    th, td { border: 1px solid #ddd; padding: 0.5rem 0.75rem; text-align: left; vertical-align: top; }
    th { background: #f4f4f4; }
    code { background: #f6f8fa; padding: 1px 4px; border-radius: 3px; font-size: 0.95em; }
    .banner { background: #e7f3ff; border-left: 4px solid #0078d4; padding: 0.75rem 1rem; margin: 1rem 0; }
    .url { word-break: break-all; }
    a.try { display: inline-block; background: #0078d4; color: #fff; padding: 0.4rem 0.8rem; border-radius: 4px; text-decoration: none; margin: 0.2rem 0.3rem 0.2rem 0; font-size: 0.9em; }
    a.try:hover { background: #106ebe; }
    a.logout { background: #666; }
  </style>
</head>
<body>
  <h1>Easy Auth — Query String Round-Trip Demo</h1>

  <div class="banner">
    You reached this page <strong>after</strong> Easy Auth redirected you to Microsoft Entra ID
    and back. Every query string parameter listed below was on the URL you originally
    requested. Easy Auth preserved them through the OAuth round trip with zero app code.
  </div>

  <h2>Full request URL</h2>
  <p class="url"><code>${esc(fullUrl)}</code></p>

  <h2>Query string parameters (round-tripped through Entra)</h2>
  <table>
    <thead><tr><th>Key</th><th>Value</th></tr></thead>
    <tbody>${queryRows}</tbody>
  </table>

  <h2>Try it</h2>
  <p>Click any link below — you'll be redirected to Entra (already signed in, so it's instant) and then back here with the query string intact.</p>
  <a class="try" href="/?nhi=12345&amp;tenant=acme&amp;view=dashboard">?nhi=12345&amp;tenant=acme&amp;view=dashboard</a>
  <a class="try" href="/?login_hint=alice@contoso.com&amp;nhi=99999&amp;feature=beta">?login_hint=alice@contoso.com&amp;nhi=99999&amp;feature=beta</a>
  <a class="try" href="/?orderId=ABC-7788&amp;source=email&amp;promo=SUMMER">?orderId=ABC-7788&amp;source=email&amp;promo=SUMMER</a>
  <a class="try" href="/landing?nhi=55555&amp;deepLink=true#section2">?nhi=55555&amp;deepLink=true#section2 (fragment test)</a>
  <br/>
  <a class="try logout" href="/.auth/logout?post_logout_redirect_uri=/">Sign out</a>

  <h2>Authenticated user (from Easy Auth headers)</h2>
  <table>
    <tbody>
      <tr><th>x-ms-client-principal-name</th><td><code>${esc(userName)}</code></td></tr>
      <tr><th>x-ms-client-principal-id</th><td><code>${esc(userId)}</code></td></tr>
      <tr><th>x-ms-client-principal-idp</th><td><code>${esc(idp)}</code></td></tr>
    </tbody>
  </table>

  <h2>Claims (decoded from x-ms-client-principal)</h2>
  <table>
    <thead><tr><th>Type</th><th>Value</th></tr></thead>
    <tbody>${claimsRows}</tbody>
  </table>

  <p style="margin-top:2rem;color:#888;font-size:0.85em;">
    Served by <code>${esc(req.hostname)}</code> · Path: <code>${esc(req.path)}</code>
  </p>
</body>
</html>`;
}

// Serve the same page for any path — keeps the demo focused on the query string,
// not on routing. Easy Auth round-trips the full path AND query string.
app.get('*', (req, res) => {
  res.set('Cache-Control', 'no-store');
  res.send(renderPage(req));
});

app.listen(port, () => {
  console.log(`Easy Auth demo listening on port ${port}`);
});
