import express, { Request, Response } from 'express';
import cookieParser from 'cookie-parser';
import * as mbuzz from 'mbuzz';
import { RequestContext, withContext } from 'mbuzz';

const app = express();

// Cookie names (must match the SDK's cookie names)
const VISITOR_COOKIE = '_mbuzz_vid';
const SESSION_COOKIE = '_mbuzz_sid';
const PORT = process.env.PORT || 4002;

// Initialize Mbuzz
mbuzz.init({
  apiKey: process.env.MBUZZ_API_KEY!,
  apiUrl: process.env.MBUZZ_API_URL || 'http://localhost:3000/api/v1',
  debug: process.env.MBUZZ_DEBUG === 'true',
});

// Middleware
app.use(cookieParser());
app.use(express.json());
app.use(mbuzz.middleware());

// Serve static HTML
app.get('/', (req: Request, res: Response) => {
  const visitorId = req.mbuzz?.visitorId || mbuzz.visitorId() || '(none)';
  const sessionId = req.mbuzz?.sessionId || mbuzz.sessionId() || '(none)';
  const userId = req.mbuzz?.userId || mbuzz.userId() || '(none)';

  res.send(`
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Mbuzz Node.js Test App</title>
  <style>
    body {
      font-family: system-ui, sans-serif;
      max-width: 800px;
      margin: 0 auto;
      padding: 20px;
      background: #f5f5f5;
    }
    h1 { color: #333; }
    .card {
      background: white;
      border-radius: 8px;
      padding: 20px;
      margin-bottom: 20px;
      box-shadow: 0 2px 4px rgba(0,0,0,0.1);
    }
    .ids {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 10px;
    }
    .id-box {
      background: #f0f0f0;
      padding: 10px;
      border-radius: 4px;
      font-family: monospace;
      font-size: 12px;
      word-break: break-all;
    }
    .id-box label {
      display: block;
      font-weight: bold;
      margin-bottom: 5px;
      font-family: system-ui, sans-serif;
    }
    form {
      display: flex;
      flex-direction: column;
      gap: 10px;
    }
    label {
      font-weight: 500;
    }
    input, textarea, button {
      padding: 10px;
      border: 1px solid #ddd;
      border-radius: 4px;
      font-size: 14px;
    }
    textarea {
      font-family: monospace;
      height: 80px;
    }
    button {
      background: #68a063;
      color: white;
      border: none;
      cursor: pointer;
    }
    button:hover {
      background: #5a8f56;
    }
    .result {
      background: #f0f0f0;
      padding: 10px;
      border-radius: 4px;
      font-family: monospace;
      font-size: 12px;
      white-space: pre-wrap;
      margin-top: 10px;
      display: none;
    }
    .result.show { display: block; }
    .success { border-left: 4px solid #4caf50; }
    .error { border-left: 4px solid #f44336; }
  </style>
</head>
<body>
  <h1>Mbuzz Node.js SDK Test App</h1>

  <div class="card">
    <h2>Current IDs</h2>
    <div class="ids">
      <div class="id-box">
        <label>Visitor ID</label>
        <span id="visitor-id">${visitorId}</span>
      </div>
      <div class="id-box">
        <label>Session ID</label>
        <span id="session-id">${sessionId}</span>
      </div>
      <div class="id-box">
        <label>User ID</label>
        <span id="user-id">${userId}</span>
      </div>
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
      <label for="conversion-user-id">User ID (optional)</label>
      <input type="text" id="conversion-user-id" name="user_id" placeholder="For acquisition tracking">
      <label>
        <input type="checkbox" id="conversion-is-acquisition" name="is_acquisition"> Is Acquisition
      </label>
      <label>
        <input type="checkbox" id="conversion-inherit-acquisition" name="inherit_acquisition"> Inherit Acquisition
      </label>
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
            try {
              data[key] = JSON.parse(value || '{}');
            } catch {
              data[key] = {};
            }
            // Auto-enrich event properties with current URL (like a browser SDK would)
            if (key === 'properties' && endpoint === '/api/event') {
              data[key].url = data[key].url || window.location.href;
            }
          } else if (key === 'revenue') {
            data[key] = value ? parseFloat(value) : null;
          } else if (key === 'is_acquisition' || key === 'inherit_acquisition') {
            data[key] = form.querySelector('[name="' + key + '"]').checked;
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
          result.className = 'result show ' + (json.success ? 'success' : 'error');
        } catch (err) {
          result.textContent = 'Error: ' + err.message;
          result.className = 'result show error';
        }
      });
    }

    submitForm('event-form', '/api/event', 'event-result');
    submitForm('identify-form', '/api/identify', 'identify-result');
    submitForm('conversion-form', '/api/conversion', 'conversion-result');

    // Refresh IDs periodically
    async function refreshIds() {
      try {
        const response = await fetch('/api/ids');
        const data = await response.json();
        document.getElementById('visitor-id').textContent = data.visitorId || '(none)';
        document.getElementById('session-id').textContent = data.sessionId || '(none)';
        document.getElementById('user-id').textContent = data.userId || '(none)';
      } catch (err) {
        console.error('Failed to refresh IDs:', err);
      }
    }

    setInterval(refreshIds, 5000);
  </script>
</body>
</html>
  `);
});

// Return current IDs as JSON
app.get('/api/ids', (req: Request, res: Response) => {
  res.json({
    visitorId: req.mbuzz?.visitorId || mbuzz.visitorId(),
    sessionId: req.mbuzz?.sessionId || mbuzz.sessionId(),
    userId: req.mbuzz?.userId || mbuzz.userId(),
  });
});

// Track event - use withContext to set up proper SDK context from cookies
app.post('/api/event', async (req: Request, res: Response) => {
  const { event_type, properties } = req.body;
  const visitorId = req.cookies[VISITOR_COOKIE];
  const sessionId = req.cookies[SESSION_COOKIE];

  if (!visitorId || !sessionId) {
    return res.json({ success: false, error: 'Missing visitor or session cookie' });
  }

  try {
    const context = new RequestContext({ visitorId, sessionId });
    const result = await withContext(context, () =>
      mbuzz.event(event_type, properties || {})
    );
    res.json({ success: result !== false, result });
  } catch (error) {
    res.json({ success: false, error: String(error) });
  }
});

// Identify user - pass visitorId explicitly from cookies
app.post('/api/identify', async (req: Request, res: Response) => {
  const { user_id, traits } = req.body;
  const visitorId = req.cookies[VISITOR_COOKIE];

  try {
    const result = await mbuzz.identify(user_id, {
      visitorId,
      traits: traits || {},
    });
    res.json({ success: result !== false, result });
  } catch (error) {
    res.json({ success: false, error: String(error) });
  }
});

// Track conversion - pass visitorId explicitly from cookies
app.post('/api/conversion', async (req: Request, res: Response) => {
  const { conversion_type, revenue, user_id, is_acquisition, inherit_acquisition, properties } =
    req.body;
  const visitorId = req.cookies[VISITOR_COOKIE];

  try {
    const result = await mbuzz.conversion(conversion_type, {
      visitorId,
      revenue,
      userId: user_id,
      isAcquisition: is_acquisition,
      inheritAcquisition: inherit_acquisition,
      properties: properties || {},
    });
    res.json({ success: result !== false, result });
  } catch (error) {
    res.json({ success: false, error: String(error) });
  }
});

// -------------------------------------------------------------------
// Background job simulation endpoints (no request context)
// These test mbuzz.event/conversion called outside middleware scope
// -------------------------------------------------------------------

// BROKEN PATTERN: No visitor_id passed - should fail after SDK fix
app.post('/api/background_event_no_visitor', async (req: Request, res: Response) => {
  const { event_type, properties } = req.body;

  try {
    // Call without visitorId - simulates background job without context
    const result = await mbuzz.event(event_type, properties || {});
    res.json({ success: result !== false, result });
  } catch (error) {
    res.json({ success: false, error: String(error) });
  }
});

// CORRECT PATTERN: Explicit visitor_id passed - should always work
app.post('/api/background_event_with_visitor', async (req: Request, res: Response) => {
  const { event_type, visitor_id, properties } = req.body;

  try {
    // Call with explicit visitorId - correct pattern for background jobs
    const result = await mbuzz.event(event_type, {
      ...properties,
      visitorId: visitor_id,
    });
    res.json({ success: result !== false, result });
  } catch (error) {
    res.json({ success: false, error: String(error) });
  }
});

// BROKEN PATTERN: No visitor_id for conversion - should fail
app.post('/api/background_conversion_no_visitor', async (req: Request, res: Response) => {
  const { conversion_type, revenue, properties } = req.body;

  try {
    // Call without visitorId - simulates background job without context
    const result = await mbuzz.conversion(conversion_type, {
      revenue,
      properties: properties || {},
    });
    res.json({ success: result !== false, result });
  } catch (error) {
    res.json({ success: false, error: String(error) });
  }
});

// CORRECT PATTERN: Explicit visitor_id for conversion - should work
app.post('/api/background_conversion_with_visitor', async (req: Request, res: Response) => {
  const { conversion_type, visitor_id, revenue, properties } = req.body;

  try {
    // Call with explicit visitorId - correct pattern for background jobs
    const result = await mbuzz.conversion(conversion_type, {
      visitorId: visitor_id,
      revenue,
      properties: properties || {},
    });
    res.json({ success: result !== false, result });
  } catch (error) {
    res.json({ success: false, error: String(error) });
  }
});

app.listen(PORT, () => {
  console.log(`Mbuzz Node.js test app running on http://localhost:${PORT}`);
});
