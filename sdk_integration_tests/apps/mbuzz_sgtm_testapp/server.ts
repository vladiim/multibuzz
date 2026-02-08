import express, { Request, Response } from 'express';
import cookieParser from 'cookie-parser';
import crypto from 'crypto';
import fs from 'fs';
import path from 'path';

const app = express();

const VISITOR_COOKIE = '_mbuzz_vid';
const PORT = process.env.PORT || 4006;
const API_URL = process.env.MBUZZ_API_URL || 'http://localhost:3000/api/v1';
const ENV_FILE = path.resolve(path.dirname(new URL(import.meta.url).pathname), '../../.test_env');

// Read API key dynamically from .test_env (written by TestSetupHelper.setup!)
// Falls back to process.env.MBUZZ_API_KEY for manual usage
function getApiKey(): string {
  try {
    const content = fs.readFileSync(ENV_FILE, 'utf-8');
    const match = content.match(/MBUZZ_API_KEY=(\S+)/);
    if (match) return match[1];
  } catch {}
  return process.env.MBUZZ_API_KEY || '';
}

app.use(cookieParser());
app.use(express.json());

// --- sGTM simulation helpers ---

function generateVisitorId(): string {
  return crypto.randomBytes(32).toString('hex');
}

function computeFingerprint(ip: string, userAgent: string): string {
  return crypto.createHash('sha256').update(`${ip}|${userAgent}`).digest('hex').substring(0, 32);
}

function generateSessionId(visitorId: string, fingerprint: string): string {
  return crypto.randomBytes(32).toString('hex');
}

async function sendToMbuzz(path: string, body: object): Promise<any> {
  const apiKey = getApiKey();
  const response = await fetch(`${API_URL}${path}`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  return response.json();
}

// --- Middleware: simulate sGTM cookie management ---

app.use((req: Request, res: Response, next) => {
  let visitorId = req.cookies[VISITOR_COOKIE];

  if (!visitorId) {
    visitorId = generateVisitorId();
    res.cookie(VISITOR_COOKIE, visitorId, {
      maxAge: 63072000000, // 2 years in ms
      path: '/',
      httpOnly: true,
      sameSite: 'lax',
    });
  }

  (req as any).visitorId = visitorId;
  next();
});

// --- Routes ---

app.get('/', (req: Request, res: Response) => {
  const visitorId = (req as any).visitorId;

  res.send(`
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>mbuzz sGTM Test App</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; background: #f5f5f5; }
    h1 { color: #333; }
    .card { background: white; border-radius: 8px; padding: 20px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
    .id-box { background: #f0f0f0; padding: 10px; border-radius: 4px; font-family: monospace; font-size: 12px; word-break: break-all; margin-bottom: 10px; }
    .id-box label { display: block; font-weight: bold; margin-bottom: 5px; font-family: system-ui, sans-serif; }
    form { display: flex; flex-direction: column; gap: 10px; }
    input, textarea, button { padding: 10px; border: 1px solid #ddd; border-radius: 4px; font-size: 14px; }
    textarea { font-family: monospace; height: 80px; }
    button { background: #4285F4; color: white; border: none; cursor: pointer; }
    button:hover { background: #3367d6; }
    .result { background: #f0f0f0; padding: 10px; border-radius: 4px; font-family: monospace; font-size: 12px; white-space: pre-wrap; margin-top: 10px; display: none; }
    .result.show { display: block; }
    .note { background: #e8f0fe; border-left: 4px solid #4285F4; padding: 12px; border-radius: 4px; margin-bottom: 15px; font-size: 14px; }
  </style>
</head>
<body>
  <h1>mbuzz sGTM Simulation Test App</h1>

  <div class="note">
    This app simulates what an sGTM tag template does: manages visitor cookies and makes direct HTTP calls to the mbuzz API. No SDK library is used.
  </div>

  <div class="card">
    <h2>Current IDs</h2>
    <div class="id-box">
      <label>Visitor ID</label>
      <span id="visitor-id">${visitorId}</span>
    </div>
  </div>

  <div class="card">
    <h2>Track Event</h2>
    <form id="event-form">
      <label for="event-type">Event Type</label>
      <input type="text" id="event-type" name="event_type" value="page_view" required>
      <label for="event-properties">Properties (JSON)</label>
      <textarea id="event-properties" name="properties">{"url": "/test-page"}</textarea>
      <button type="submit">Track Event</button>
    </form>
    <div class="result" id="event-result"></div>
  </div>

  <div class="card">
    <h2>Identify User</h2>
    <form id="identify-form">
      <label for="identify-user-id">User ID</label>
      <input type="text" id="identify-user-id" name="user_id" value="test_user_123" required>
      <label for="identify-traits">Traits (JSON)</label>
      <textarea id="identify-traits" name="traits">{"email": "test@example.com", "name": "Test User"}</textarea>
      <button type="submit">Identify</button>
    </form>
    <div class="result" id="identify-result"></div>
  </div>

  <div class="card">
    <h2>Track Conversion</h2>
    <form id="conversion-form">
      <label for="conversion-type">Conversion Type</label>
      <input type="text" id="conversion-type" name="conversion_type" value="purchase" required>
      <label for="conversion-revenue">Revenue</label>
      <input type="number" id="conversion-revenue" name="revenue" step="0.01" value="99.99">
      <label for="conversion-properties">Properties (JSON)</label>
      <textarea id="conversion-properties" name="properties">{"orderId": "ORD-123"}</textarea>
      <button type="submit">Track Conversion</button>
    </form>
    <div class="result" id="conversion-result"></div>
  </div>

  <script>
    async function submitForm(formId, endpoint, resultId) {
      const form = document.getElementById(formId);
      const result = document.getElementById(resultId);
      form.addEventListener('submit', async (e) => {
        e.preventDefault();
        const formData = new FormData(form);
        const data = {};
        for (const [key, value] of formData.entries()) {
          if (key === 'properties' || key === 'traits') {
            try { data[key] = JSON.parse(value || '{}'); } catch { data[key] = {}; }
          } else if (key === 'revenue') {
            data[key] = value ? parseFloat(value) : null;
          } else {
            data[key] = value;
          }
        }
        try {
          const response = await fetch(endpoint, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data)
          });
          const json = await response.json();
          result.textContent = JSON.stringify(json, null, 2);
          result.className = 'result show';
        } catch (err) {
          result.textContent = 'Error: ' + err.message;
          result.className = 'result show';
        }
      });
    }
    submitForm('event-form', '/api/event', 'event-result');
    submitForm('identify-form', '/api/identify', 'identify-result');
    submitForm('conversion-form', '/api/conversion', 'conversion-result');
  </script>
</body>
</html>
  `);
});

// --- API proxy routes (simulate sGTM tag calls) ---

// Session creation: what the sGTM session tag does
app.post('/api/session', async (req: Request, res: Response) => {
  const visitorId = (req as any).visitorId;
  const ip = req.ip || '127.0.0.1';
  const userAgent = req.get('user-agent') || 'sGTM-test';
  const fingerprint = computeFingerprint(ip, userAgent);
  const sessionId = generateSessionId(visitorId, fingerprint);

  const { url, referrer } = req.body;

  try {
    const result = await sendToMbuzz('/sessions', {
      session: {
        visitor_id: visitorId,
        session_id: sessionId,
        url: url || `http://localhost:${PORT}/`,
        referrer: referrer || undefined,
        device_fingerprint: fingerprint,
        started_at: new Date().toISOString(),
      }
    });
    res.json({ success: result.status === 'accepted', ...result });
  } catch (error) {
    res.json({ success: false, error: String(error) });
  }
});

// Event tracking: what the sGTM event tag does
app.post('/api/event', async (req: Request, res: Response) => {
  const visitorId = (req as any).visitorId;
  const ip = req.ip || '127.0.0.1';
  const userAgent = req.get('user-agent') || 'sGTM-test';
  const { event_type, properties } = req.body;

  try {
    const result = await sendToMbuzz('/events', {
      events: [{
        event_type: event_type || 'page_view',
        visitor_id: visitorId,
        ip,
        user_agent: userAgent,
        properties: properties || {},
        timestamp: new Date().toISOString(),
      }]
    });
    res.json({ success: (result.accepted || 0) > 0, ...result });
  } catch (error) {
    res.json({ success: false, error: String(error) });
  }
});

// Conversion tracking: what the sGTM conversion tag does
app.post('/api/conversion', async (req: Request, res: Response) => {
  const visitorId = (req as any).visitorId;
  const ip = req.ip || '127.0.0.1';
  const userAgent = req.get('user-agent') || 'sGTM-test';
  const { conversion_type, revenue, currency, properties } = req.body;

  try {
    const result = await sendToMbuzz('/conversions', {
      conversion: {
        visitor_id: visitorId,
        conversion_type: conversion_type || 'purchase',
        revenue: revenue ? parseFloat(revenue) : undefined,
        currency: currency || 'USD',
        ip,
        user_agent: userAgent,
        properties: properties || {},
      }
    });
    res.json({ success: !!result.conversion, ...result });
  } catch (error) {
    res.json({ success: false, error: String(error) });
  }
});

// Identify: what the sGTM identify tag does
app.post('/api/identify', async (req: Request, res: Response) => {
  const visitorId = (req as any).visitorId;
  const { user_id, traits } = req.body;

  try {
    const result = await sendToMbuzz('/identify', {
      user_id,
      visitor_id: visitorId,
      traits: traits || {},
    });
    res.json({ success: result.success === true, ...result });
  } catch (error) {
    res.json({ success: false, error: String(error) });
  }
});

app.listen(PORT, () => {
  console.log(`mbuzz sGTM simulation test app running on http://localhost:${PORT}`);
});
