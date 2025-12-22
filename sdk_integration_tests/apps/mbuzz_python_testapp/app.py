"""Flask test app for mbuzz Python SDK integration testing."""

import json
import os
from pathlib import Path
from flask import Flask, request, jsonify, render_template_string

import mbuzz
from mbuzz.config import config as mbuzz_config
from mbuzz.middleware.flask import init_app

app = Flask(__name__)
app.secret_key = os.environ.get("SECRET_KEY", "test-secret-key")

# Path to test env file written by test framework
TEST_ENV_FILE = Path(__file__).parent.parent.parent / ".test_env"


def load_test_env():
    """Load API key from test env file if it exists."""
    if TEST_ENV_FILE.exists():
        env_vars = {}
        for line in TEST_ENV_FILE.read_text().strip().split("\n"):
            if "=" in line:
                key, value = line.split("=", 1)
                env_vars[key] = value
        return env_vars
    return {}


def get_api_config():
    """Get API key and URL, preferring test env file."""
    test_env = load_test_env()
    api_key = test_env.get("MBUZZ_API_KEY") or os.environ.get("MBUZZ_API_KEY", "sk_test_integration")
    api_url = test_env.get("MBUZZ_API_URL") or os.environ.get("MBUZZ_API_URL", "http://localhost:3000/api/v1")
    return api_key, api_url


# Initial mbuzz config
api_key, api_url = get_api_config()
mbuzz.init(api_key=api_key, api_url=api_url)

# Initialize middleware
init_app(app)


@app.before_request
def check_api_key():
    """Re-initialize mbuzz if API key changed (for test framework)."""
    api_key, api_url = get_api_config()
    if mbuzz_config.api_key != api_key:
        mbuzz_config.reset()
        mbuzz.init(api_key=api_key, api_url=api_url)

INDEX_HTML = """
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Mbuzz Python Test App</title>
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
      background: #4a90d9;
      color: white;
      border: none;
      cursor: pointer;
    }
    button:hover {
      background: #357abd;
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
  <h1>Mbuzz Python SDK Test App</h1>

  <div class="card">
    <h2>Current IDs</h2>
    <div class="ids">
      <div class="id-box">
        <label>Visitor ID</label>
        <span id="visitor-id">{{ visitor_id }}</span>
      </div>
      <div class="id-box">
        <label>Session ID</label>
        <span id="session-id">{{ session_id }}</span>
      </div>
      <div class="id-box">
        <label>User ID</label>
        <span id="user-id">{{ user_id or "(none)" }}</span>
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
      <textarea id="conversion-properties" name="properties">{"order_id": "ORD-123"}</textarea>
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

        // Handle text inputs
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
            data[key] = form.querySelector(`[name="${key}"]`).checked;
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
        document.getElementById('visitor-id').textContent = data.visitor_id || '(none)';
        document.getElementById('session-id').textContent = data.session_id || '(none)';
        document.getElementById('user-id').textContent = data.user_id || '(none)';
      } catch (err) {
        console.error('Failed to refresh IDs:', err);
      }
    }

    setInterval(refreshIds, 5000);
  </script>
</body>
</html>
"""


@app.route("/")
def index():
    """Main page with test forms."""
    return render_template_string(
        INDEX_HTML,
        visitor_id=mbuzz.visitor_id(),
        session_id=mbuzz.session_id(),
        user_id=mbuzz.user_id(),
    )


@app.route("/api/ids")
def get_ids():
    """Return current tracking IDs."""
    return jsonify({
        "visitor_id": mbuzz.visitor_id(),
        "session_id": mbuzz.session_id(),
        "user_id": mbuzz.user_id(),
    })


@app.route("/api/event", methods=["POST"])
def track_event():
    """Track an event."""
    data = request.get_json()
    event_type = data.get("event_type", "page_view")
    properties = data.get("properties", {})

    result = mbuzz.event(event_type, **properties)

    return jsonify({
        "success": result.success,
        "event_id": result.event_id,
        "event_type": result.event_type,
        "visitor_id": result.visitor_id,
        "session_id": result.session_id,
    })


@app.route("/api/identify", methods=["POST"])
def identify_user():
    """Identify a user."""
    data = request.get_json()
    user_id = data.get("user_id")
    traits = data.get("traits", {})

    success = mbuzz.identify(user_id, traits=traits)

    return jsonify({
        "success": success,
        "user_id": user_id,
    })


@app.route("/api/conversion", methods=["POST"])
def track_conversion():
    """Track a conversion."""
    data = request.get_json()
    conversion_type = data.get("conversion_type", "purchase")
    revenue = data.get("revenue")
    user_id = data.get("user_id") or None
    is_acquisition = data.get("is_acquisition", False)
    inherit_acquisition = data.get("inherit_acquisition", False)
    properties = data.get("properties", {})

    result = mbuzz.conversion(
        conversion_type,
        user_id=user_id,
        revenue=revenue,
        is_acquisition=is_acquisition,
        inherit_acquisition=inherit_acquisition,
        properties=properties,
    )

    return jsonify({
        "success": result.success,
        "conversion_id": result.conversion_id,
        "attribution": result.attribution,
    })


if __name__ == "__main__":
    app.run(port=4003, debug=True)
