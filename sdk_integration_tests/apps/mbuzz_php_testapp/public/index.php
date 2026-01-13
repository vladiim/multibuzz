<?php

declare(strict_types=1);

require_once __DIR__ . '/../vendor/autoload.php';

use Mbuzz\Mbuzz;

// Load test env file if it exists
// Path: public -> mbuzz_php_testapp -> apps -> sdk_integration_tests (3 levels up)
$testEnvFile = __DIR__ . '/../../../.test_env';
$envVars = [];
if (file_exists($testEnvFile)) {
    foreach (file($testEnvFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
        if (str_contains($line, '=')) {
            [$key, $value] = explode('=', $line, 2);
            $envVars[$key] = $value;
        }
    }
}

$apiKey = $envVars['MBUZZ_API_KEY'] ?? getenv('MBUZZ_API_KEY') ?: 'sk_test_integration';
$apiUrl = $envVars['MBUZZ_API_URL'] ?? getenv('MBUZZ_API_URL') ?: 'http://localhost:3000/api/v1';

// Initialize Mbuzz
Mbuzz::init([
    'api_key' => $apiKey,
    'api_url' => $apiUrl,
    'debug' => (getenv('MBUZZ_DEBUG') ?: 'false') === 'true',
]);

// Initialize from request (reads cookies, creates session)
Mbuzz::initFromRequest();

// Simple router
$method = $_SERVER['REQUEST_METHOD'];
$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);

// Set JSON content type for API routes
if (str_starts_with($path, '/api/')) {
    header('Content-Type: application/json');
}

switch (true) {
    case $path === '/' && $method === 'GET':
        renderIndex();
        break;

    case $path === '/api/ids' && $method === 'GET':
        echo json_encode([
            'visitor_id' => Mbuzz::visitorId(),
            'session_id' => Mbuzz::sessionId(),
            'user_id' => Mbuzz::userId(),
        ]);
        break;

    case $path === '/api/event' && $method === 'POST':
        $data = json_decode(file_get_contents('php://input'), true) ?? [];
        $eventType = $data['event_type'] ?? 'page_view';
        $properties = $data['properties'] ?? [];

        $result = Mbuzz::event($eventType, $properties);

        if ($result === false) {
            echo json_encode([
                'success' => false,
                'event_id' => null,
                'event_type' => $eventType,
                'visitor_id' => Mbuzz::visitorId(),
                'session_id' => Mbuzz::sessionId(),
            ]);
        } else {
            echo json_encode($result);
        }
        break;

    case $path === '/api/identify' && $method === 'POST':
        $data = json_decode(file_get_contents('php://input'), true) ?? [];
        $userId = $data['user_id'] ?? '';
        $traits = $data['traits'] ?? [];

        $success = Mbuzz::identify($userId, $traits);

        echo json_encode([
            'success' => $success,
            'user_id' => $userId,
        ]);
        break;

    case $path === '/api/conversion' && $method === 'POST':
        $data = json_decode(file_get_contents('php://input'), true) ?? [];
        $conversionType = $data['conversion_type'] ?? 'purchase';

        $options = [];
        if (isset($data['revenue'])) {
            $options['revenue'] = (float) $data['revenue'];
        }
        if (isset($data['user_id']) && $data['user_id'] !== '') {
            $options['user_id'] = $data['user_id'];
        }
        if (isset($data['is_acquisition'])) {
            $options['is_acquisition'] = (bool) $data['is_acquisition'];
        }
        if (isset($data['inherit_acquisition'])) {
            $options['inherit_acquisition'] = (bool) $data['inherit_acquisition'];
        }
        if (isset($data['properties'])) {
            $options['properties'] = $data['properties'];
        }

        $result = Mbuzz::conversion($conversionType, $options);

        if ($result === false) {
            echo json_encode([
                'success' => false,
                'conversion_id' => null,
                'attribution' => null,
            ]);
        } else {
            echo json_encode($result);
        }
        break;

    // -------------------------------------------------------------------
    // Background job simulation endpoints (no request context)
    // These test Mbuzz::event/conversion called outside middleware scope
    // -------------------------------------------------------------------

    // BROKEN PATTERN: No visitor_id passed - should fail after SDK fix
    case $path === '/api/background_event_no_visitor' && $method === 'POST':
        $data = json_decode(file_get_contents('php://input'), true) ?? [];
        $eventType = $data['event_type'] ?? 'background_test';
        $properties = $data['properties'] ?? [];

        // Call without visitor_id - simulates background job without context
        $result = Mbuzz::event($eventType, $properties);

        echo json_encode([
            'success' => $result !== false,
            'result' => $result,
        ]);
        break;

    // CORRECT PATTERN: Explicit visitor_id passed - should always work
    case $path === '/api/background_event_with_visitor' && $method === 'POST':
        $data = json_decode(file_get_contents('php://input'), true) ?? [];
        $eventType = $data['event_type'] ?? 'background_test';
        $visitorId = $data['visitor_id'] ?? null;
        $properties = $data['properties'] ?? [];

        // Call with explicit visitor_id - correct pattern for background jobs
        $result = Mbuzz::event($eventType, $properties, $visitorId);

        echo json_encode([
            'success' => $result !== false,
            'result' => $result,
        ]);
        break;

    // BROKEN PATTERN: No visitor_id for conversion - should fail
    case $path === '/api/background_conversion_no_visitor' && $method === 'POST':
        $data = json_decode(file_get_contents('php://input'), true) ?? [];
        $conversionType = $data['conversion_type'] ?? 'background_purchase';

        $options = [];
        if (isset($data['revenue'])) {
            $options['revenue'] = (float) $data['revenue'];
        }
        if (isset($data['properties'])) {
            $options['properties'] = $data['properties'];
        }

        // Call without visitor_id - simulates background job without context
        $result = Mbuzz::conversion($conversionType, $options);

        echo json_encode([
            'success' => $result !== false,
            'result' => $result,
        ]);
        break;

    // CORRECT PATTERN: Explicit visitor_id for conversion - should work
    case $path === '/api/background_conversion_with_visitor' && $method === 'POST':
        $data = json_decode(file_get_contents('php://input'), true) ?? [];
        $conversionType = $data['conversion_type'] ?? 'background_purchase';
        $visitorId = $data['visitor_id'] ?? null;

        $options = [];
        if ($visitorId !== null) {
            $options['visitor_id'] = $visitorId;
        }
        if (isset($data['revenue'])) {
            $options['revenue'] = (float) $data['revenue'];
        }
        if (isset($data['properties'])) {
            $options['properties'] = $data['properties'];
        }

        // Call with explicit visitor_id - correct pattern for background jobs
        $result = Mbuzz::conversion($conversionType, $options);

        echo json_encode([
            'success' => $result !== false,
            'result' => $result,
        ]);
        break;

    default:
        http_response_code(404);
        echo json_encode(['error' => 'Not Found']);
        break;
}

function renderIndex(): void
{
    $visitorId = Mbuzz::visitorId() ?? '';
    $sessionId = Mbuzz::sessionId() ?? '';
    $userId = Mbuzz::userId() ?? '(none)';

    echo <<<HTML
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Mbuzz PHP Test App</title>
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
  <h1>Mbuzz PHP SDK Test App</h1>

  <div class="card">
    <h2>Current IDs</h2>
    <div class="ids">
      <div class="id-box">
        <label>Visitor ID</label>
        <span id="visitor-id">{$visitorId}</span>
      </div>
      <div class="id-box">
        <label>Session ID</label>
        <span id="session-id">{$sessionId}</span>
      </div>
      <div class="id-box">
        <label>User ID</label>
        <span id="user-id">{$userId}</span>
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

        for (const [key, value] of formData.entries()) {
          if (key === 'properties' || key === 'traits') {
            try {
              data[key] = JSON.parse(value || '{}');
            } catch {
              data[key] = {};
            }
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
HTML;
}
