# PHP SDK Specification

**Status**: Research Complete - Ready for Implementation
**Last Updated**: 2025-12-17
**Target**: PHP 8.1+, Framework Agnostic

---

## Overview

Server-side multi-touch attribution SDK for PHP. Framework-agnostic design using PSR standards, with optional adapters for Laravel, Symfony, and other frameworks.

### Design Principles

1. **Zero Required Dependencies** - Core SDK works with native PHP
2. **PSR Compliant** - Uses PSR-18 (HTTP), PSR-7 (Messages), PSR-15 (Middleware) interfaces
3. **Framework Agnostic** - Works without any framework; adapters are optional
4. **Bring Your Own HTTP Client** - Supports Guzzle, Symfony HttpClient, or any PSR-18 client
5. **Never Throw Exceptions** - All methods return false on failure
6. **Fire and Forget** - Async-friendly, non-blocking design

### Package Info

**Package name**: `mbuzz/mbuzz-php`
**Packagist**: `composer require mbuzz/mbuzz-php`
**Repo**: `https://github.com/mbuzz-tracking/mbuzz-php`

---

## Architecture Comparison

| Component | Ruby | Python | Node.js | **PHP** |
|-----------|------|--------|---------|---------|
| HTTP Client | Net::HTTP | urllib/requests | node:https | cURL / PSR-18 |
| Context Storage | Thread.current | contextvars | AsyncLocalStorage | Static/Singleton |
| ID Generation | SecureRandom.hex | secrets.token_hex | crypto.randomBytes | random_bytes |
| Cookie Read | request.cookies | request.COOKIES | req.cookies | $_COOKIE |
| Cookie Write | Set-Cookie header | response.set_cookie | res.cookie() | setcookie() |
| Middleware | Rack | WSGI/ASGI | Express middleware | PSR-15 / native |
| Package Manager | RubyGems | PyPI | npm | Composer |

### PHP-Specific Considerations

1. **Stateless by default** - Each PHP request starts fresh (unlike Node.js persistent processes)
2. **No context propagation needed** - Request data available via superglobals
3. **Static properties risk** - Can persist in long-running processes (PHP-FPM, Swoole, ReactPHP)
4. **Superglobals available** - `$_COOKIE`, `$_SERVER`, `$_GET` always accessible

---

## Public API

```php
<?php

use Mbuzz\Mbuzz;

// Initialize (once on app bootstrap)
Mbuzz::init([
    'api_key' => $_ENV['MBUZZ_API_KEY'],
    'debug' => true,
]);

// Track journey events
Mbuzz::event('page_view', ['url' => 'https://example.com']);
Mbuzz::event('add_to_cart', ['product_id' => 'SKU-123', 'price' => 49.99]);

// Track conversions
Mbuzz::conversion('purchase', [
    'revenue' => 99.99,
    'order_id' => 'ORD-123',
]);

// Acquisition conversion (marks first touchpoint)
Mbuzz::conversion('signup', [
    'user_id' => $user->id,
    'is_acquisition' => true,
]);

// Recurring revenue (inherits acquisition attribution)
Mbuzz::conversion('payment', [
    'user_id' => $user->id,
    'revenue' => 49.00,
    'inherit_acquisition' => true,
]);

// Link visitor to user identity
Mbuzz::identify($user->id, [
    'email' => $user->email,
    'name' => $user->name,
    'plan' => 'pro',
]);

// Context accessors
Mbuzz::visitorId();   // Current visitor ID
Mbuzz::sessionId();   // Current session ID
Mbuzz::userId();      // Current user ID (if set)
```

---

## Directory Structure

```
mbuzz-php/
├── composer.json           # Package config
├── README.md
├── LICENSE
├── CHANGELOG.md
├── src/
│   └── Mbuzz/
│       ├── Mbuzz.php               # Static facade (public API)
│       ├── Client.php              # Core client orchestrator
│       ├── Config.php              # Configuration singleton
│       ├── Context.php             # Request context (visitor/session/user)
│       ├── Api.php                 # HTTP client abstraction
│       ├── CookieManager.php       # Cookie read/write abstraction
│       ├── IdGenerator.php         # Secure ID generation
│       │
│       ├── Request/
│       │   ├── TrackRequest.php    # Event tracking
│       │   ├── IdentifyRequest.php # User identification
│       │   ├── ConversionRequest.php # Conversion tracking
│       │   └── SessionRequest.php  # Session creation
│       │
│       ├── Middleware/
│       │   ├── TrackingMiddleware.php    # PSR-15 middleware
│       │   └── NativeMiddleware.php      # Plain PHP middleware
│       │
│       └── Adapter/
│           ├── LaravelServiceProvider.php
│           ├── LaravelMiddleware.php
│           ├── SymfonyBundle.php
│           └── SlimMiddleware.php
│
└── tests/
    ├── Unit/
    │   ├── ConfigTest.php
    │   ├── ContextTest.php
    │   ├── ApiTest.php
    │   └── Request/
    └── Integration/
        └── TrackingTest.php
```

---

## Core Components

### 1. Configuration (`Config.php`)

```php
<?php

declare(strict_types=1);

namespace Mbuzz;

final class Config
{
    private const DEFAULT_API_URL = 'https://mbuzz.co/api/v1';
    private const DEFAULT_TIMEOUT = 5;

    private const DEFAULT_SKIP_PATHS = [
        '/health', '/healthz', '/ping', '/up',
        '/favicon.ico', '/robots.txt',
    ];

    private const DEFAULT_SKIP_EXTENSIONS = [
        '.js', '.css', '.map',
        '.png', '.jpg', '.jpeg', '.gif', '.ico', '.svg', '.webp',
        '.woff', '.woff2', '.ttf', '.eot',
    ];

    private static ?self $instance = null;

    private string $apiKey = '';
    private string $apiUrl = self::DEFAULT_API_URL;
    private bool $enabled = true;
    private bool $debug = false;
    private int $timeout = self::DEFAULT_TIMEOUT;
    private array $skipPaths = [];
    private array $skipExtensions = [];
    private bool $initialized = false;

    private function __construct() {}

    public static function getInstance(): self
    {
        if (self::$instance === null) {
            self::$instance = new self();
        }
        return self::$instance;
    }

    /**
     * Reset singleton (for testing only)
     */
    public static function reset(): void
    {
        self::$instance = null;
    }

    public function init(array $options): void
    {
        $apiKey = $options['api_key'] ?? '';
        if (empty($apiKey)) {
            throw new \InvalidArgumentException('api_key is required');
        }

        $this->apiKey = $apiKey;
        $this->apiUrl = $options['api_url'] ?? self::DEFAULT_API_URL;
        $this->enabled = $options['enabled'] ?? true;
        $this->debug = $options['debug'] ?? false;
        $this->timeout = $options['timeout'] ?? self::DEFAULT_TIMEOUT;
        $this->skipPaths = array_merge(
            self::DEFAULT_SKIP_PATHS,
            $options['skip_paths'] ?? []
        );
        $this->skipExtensions = array_merge(
            self::DEFAULT_SKIP_EXTENSIONS,
            $options['skip_extensions'] ?? []
        );
        $this->initialized = true;
    }

    public function isInitialized(): bool
    {
        return $this->initialized;
    }

    public function isEnabled(): bool
    {
        return $this->enabled && $this->initialized;
    }

    public function getApiKey(): string
    {
        return $this->apiKey;
    }

    public function getApiUrl(): string
    {
        return rtrim($this->apiUrl, '/');
    }

    public function isDebug(): bool
    {
        return $this->debug;
    }

    public function getTimeout(): int
    {
        return $this->timeout;
    }

    public function shouldSkipPath(string $path): bool
    {
        // Check exact path matches
        foreach ($this->skipPaths as $skipPath) {
            if (str_starts_with($path, $skipPath)) {
                return true;
            }
        }

        // Check extension matches
        foreach ($this->skipExtensions as $ext) {
            if (str_ends_with($path, $ext)) {
                return true;
            }
        }

        return false;
    }

    public function isTestKey(): bool
    {
        return str_starts_with($this->apiKey, 'sk_test_');
    }
}
```

### 2. HTTP Client (`Api.php`)

Framework-agnostic HTTP client with PSR-18 support and cURL fallback.

```php
<?php

declare(strict_types=1);

namespace Mbuzz;

use Psr\Http\Client\ClientInterface;
use Psr\Http\Message\RequestFactoryInterface;
use Psr\Http\Message\StreamFactoryInterface;

final class Api
{
    private const USER_AGENT = 'mbuzz-php/0.1.0';

    private Config $config;
    private ?ClientInterface $httpClient = null;
    private ?RequestFactoryInterface $requestFactory = null;
    private ?StreamFactoryInterface $streamFactory = null;

    public function __construct(Config $config)
    {
        $this->config = $config;
    }

    /**
     * Inject PSR-18 HTTP client (optional - uses cURL if not provided)
     */
    public function setHttpClient(
        ClientInterface $client,
        RequestFactoryInterface $requestFactory,
        StreamFactoryInterface $streamFactory
    ): void {
        $this->httpClient = $client;
        $this->requestFactory = $requestFactory;
        $this->streamFactory = $streamFactory;
    }

    /**
     * POST request, returns boolean (fire-and-forget)
     */
    public function post(string $path, array $payload): bool
    {
        if (!$this->config->isEnabled()) {
            return false;
        }

        try {
            $response = $this->sendRequest('POST', $path, $payload);
            return $response['status'] >= 200 && $response['status'] < 300;
        } catch (\Throwable $e) {
            $this->log("API error: {$e->getMessage()}");
            return false;
        }
    }

    /**
     * POST request, returns parsed JSON response
     */
    public function postWithResponse(string $path, array $payload): ?array
    {
        if (!$this->config->isEnabled()) {
            return null;
        }

        try {
            $response = $this->sendRequest('POST', $path, $payload);
            if ($response['status'] >= 200 && $response['status'] < 300) {
                return $response['body'];
            }
            return null;
        } catch (\Throwable $e) {
            $this->log("API error: {$e->getMessage()}");
            return null;
        }
    }

    /**
     * GET request for validation
     */
    public function get(string $path): ?array
    {
        if (!$this->config->isEnabled()) {
            return null;
        }

        try {
            $response = $this->sendRequest('GET', $path, null);
            if ($response['status'] >= 200 && $response['status'] < 300) {
                return $response['body'];
            }
            return null;
        } catch (\Throwable $e) {
            $this->log("API error: {$e->getMessage()}");
            return null;
        }
    }

    private function sendRequest(string $method, string $path, ?array $payload): array
    {
        // Use PSR-18 client if available, otherwise fall back to cURL
        if ($this->httpClient !== null) {
            return $this->sendPsrRequest($method, $path, $payload);
        }

        return $this->sendCurlRequest($method, $path, $payload);
    }

    private function sendPsrRequest(string $method, string $path, ?array $payload): array
    {
        $url = $this->config->getApiUrl() . '/' . ltrim($path, '/');

        $request = $this->requestFactory->createRequest($method, $url)
            ->withHeader('Authorization', 'Bearer ' . $this->config->getApiKey())
            ->withHeader('Content-Type', 'application/json')
            ->withHeader('User-Agent', self::USER_AGENT);

        if ($payload !== null) {
            $body = $this->streamFactory->createStream(json_encode($payload));
            $request = $request->withBody($body);
        }

        $this->log("Request: {$method} {$url}", $payload ?? []);

        $response = $this->httpClient->sendRequest($request);
        $status = $response->getStatusCode();
        $body = json_decode((string) $response->getBody(), true);

        $this->log("Response: {$status}", $body ?? []);

        return ['status' => $status, 'body' => $body];
    }

    private function sendCurlRequest(string $method, string $path, ?array $payload): array
    {
        $url = $this->config->getApiUrl() . '/' . ltrim($path, '/');

        $ch = curl_init();
        curl_setopt_array($ch, [
            CURLOPT_URL => $url,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => $this->config->getTimeout(),
            CURLOPT_CONNECTTIMEOUT => $this->config->getTimeout(),
            CURLOPT_HTTPHEADER => [
                'Authorization: Bearer ' . $this->config->getApiKey(),
                'Content-Type: application/json',
                'User-Agent: ' . self::USER_AGENT,
            ],
        ]);

        if ($method === 'POST' && $payload !== null) {
            curl_setopt($ch, CURLOPT_POST, true);
            curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($payload));
        }

        $this->log("Request: {$method} {$url}", $payload ?? []);

        $response = curl_exec($ch);
        $status = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $error = curl_error($ch);
        curl_close($ch);

        if ($response === false) {
            throw new \RuntimeException("cURL error: {$error}");
        }

        $body = json_decode($response, true);

        $this->log("Response: {$status}", $body ?? []);

        return ['status' => $status, 'body' => $body];
    }

    private function log(string $message, array $context = []): void
    {
        if ($this->config->isDebug()) {
            $contextStr = empty($context) ? '' : ' ' . json_encode($context);
            error_log("[Mbuzz] {$message}{$contextStr}");
        }
    }
}
```

### 3. ID Generator (`IdGenerator.php`)

```php
<?php

declare(strict_types=1);

namespace Mbuzz;

final class IdGenerator
{
    /**
     * Generate 64-character hex string (256 bits of entropy)
     */
    public static function generate(): string
    {
        return bin2hex(random_bytes(32));
    }
}
```

### 4. Cookie Manager (`CookieManager.php`)

Framework-agnostic cookie handling using native PHP.

```php
<?php

declare(strict_types=1);

namespace Mbuzz;

final class CookieManager
{
    public const VISITOR_COOKIE = '_mbuzz_vid';
    public const SESSION_COOKIE = '_mbuzz_sid';

    public const VISITOR_MAX_AGE = 63072000; // 2 years in seconds
    public const SESSION_MAX_AGE = 1800;     // 30 minutes in seconds

    private bool $secure = true;
    private string $path = '/';
    private string $sameSite = 'Lax';

    public function __construct()
    {
        // Auto-detect secure based on request
        $this->secure = $this->isSecureRequest();
    }

    /**
     * Get cookie value, returns null if not set
     */
    public function get(string $name): ?string
    {
        return $_COOKIE[$name] ?? null;
    }

    /**
     * Set cookie with proper attributes
     */
    public function set(string $name, string $value, int $maxAge): bool
    {
        // Don't try to set cookies if headers already sent
        if (headers_sent()) {
            return false;
        }

        $options = [
            'expires' => time() + $maxAge,
            'path' => $this->path,
            'secure' => $this->secure,
            'httponly' => true,
            'samesite' => $this->sameSite,
        ];

        return setcookie($name, $value, $options);
    }

    /**
     * Delete cookie
     */
    public function delete(string $name): bool
    {
        if (headers_sent()) {
            return false;
        }

        $options = [
            'expires' => time() - 3600,
            'path' => $this->path,
        ];

        unset($_COOKIE[$name]);
        return setcookie($name, '', $options);
    }

    /**
     * Get visitor ID cookie, or null if not set
     */
    public function getVisitorId(): ?string
    {
        return $this->get(self::VISITOR_COOKIE);
    }

    /**
     * Get session ID cookie, or null if not set
     */
    public function getSessionId(): ?string
    {
        return $this->get(self::SESSION_COOKIE);
    }

    /**
     * Set visitor ID cookie
     */
    public function setVisitorId(string $visitorId): bool
    {
        return $this->set(self::VISITOR_COOKIE, $visitorId, self::VISITOR_MAX_AGE);
    }

    /**
     * Set session ID cookie
     */
    public function setSessionId(string $sessionId): bool
    {
        return $this->set(self::SESSION_COOKIE, $sessionId, self::SESSION_MAX_AGE);
    }

    /**
     * Check if visitor is new (no visitor cookie)
     */
    public function isNewVisitor(): bool
    {
        return $this->getVisitorId() === null;
    }

    /**
     * Check if session is new (no session cookie)
     */
    public function isNewSession(): bool
    {
        return $this->getSessionId() === null;
    }

    private function isSecureRequest(): bool
    {
        return (
            (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ||
            ($_SERVER['SERVER_PORT'] ?? 0) == 443 ||
            ($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https'
        );
    }
}
```

### 5. Request Context (`Context.php`)

Manages per-request state. Uses static storage (safe in PHP's request-per-process model).

```php
<?php

declare(strict_types=1);

namespace Mbuzz;

final class Context
{
    private static ?self $instance = null;

    private ?string $visitorId = null;
    private ?string $sessionId = null;
    private ?string $userId = null;
    private ?string $url = null;
    private ?string $referrer = null;
    private bool $isNewSession = false;
    private bool $initialized = false;

    private function __construct() {}

    public static function getInstance(): self
    {
        if (self::$instance === null) {
            self::$instance = new self();
        }
        return self::$instance;
    }

    /**
     * Reset context (for new requests in long-running processes)
     */
    public static function reset(): void
    {
        self::$instance = null;
    }

    /**
     * Initialize context from cookies and request
     */
    public function initialize(CookieManager $cookies): void
    {
        if ($this->initialized) {
            return;
        }

        // Get or create visitor ID
        $this->visitorId = $cookies->getVisitorId() ?? IdGenerator::generate();
        $isNewVisitor = $cookies->isNewVisitor();

        // Get or create session ID
        $this->sessionId = $cookies->getSessionId() ?? IdGenerator::generate();
        $this->isNewSession = $cookies->isNewSession();

        // Extract request info
        $this->url = $this->extractUrl();
        $this->referrer = $_SERVER['HTTP_REFERER'] ?? null;

        // Set cookies
        if ($isNewVisitor) {
            $cookies->setVisitorId($this->visitorId);
        }
        $cookies->setSessionId($this->sessionId); // Always refresh session cookie

        $this->initialized = true;
    }

    public function isInitialized(): bool
    {
        return $this->initialized;
    }

    public function getVisitorId(): ?string
    {
        return $this->visitorId;
    }

    public function setVisitorId(string $visitorId): void
    {
        $this->visitorId = $visitorId;
    }

    public function getSessionId(): ?string
    {
        return $this->sessionId;
    }

    public function getUserId(): ?string
    {
        return $this->userId;
    }

    public function setUserId(string $userId): void
    {
        $this->userId = $userId;
    }

    public function getUrl(): ?string
    {
        return $this->url;
    }

    public function getReferrer(): ?string
    {
        return $this->referrer;
    }

    public function isNewSession(): bool
    {
        return $this->isNewSession;
    }

    /**
     * Enrich properties with URL and referrer
     */
    public function enrichProperties(array $properties = []): array
    {
        $enriched = [];

        if ($this->url !== null && !isset($properties['url'])) {
            $enriched['url'] = $this->url;
        }

        if ($this->referrer !== null && !isset($properties['referrer'])) {
            $enriched['referrer'] = $this->referrer;
        }

        return array_merge($enriched, $properties);
    }

    private function extractUrl(): ?string
    {
        $scheme = $this->isSecure() ? 'https' : 'http';
        $host = $_SERVER['HTTP_HOST'] ?? $_SERVER['SERVER_NAME'] ?? null;
        $uri = $_SERVER['REQUEST_URI'] ?? '/';

        if ($host === null) {
            return null;
        }

        return "{$scheme}://{$host}{$uri}";
    }

    private function isSecure(): bool
    {
        return (
            (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ||
            ($_SERVER['SERVER_PORT'] ?? 0) == 443 ||
            ($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https'
        );
    }
}
```

### 6. Static Facade (`Mbuzz.php`)

The main public API - a static facade similar to Laravel's patterns.

```php
<?php

declare(strict_types=1);

namespace Mbuzz;

use Mbuzz\Request\TrackRequest;
use Mbuzz\Request\IdentifyRequest;
use Mbuzz\Request\ConversionRequest;
use Mbuzz\Request\SessionRequest;

final class Mbuzz
{
    private static ?Client $client = null;

    /**
     * Initialize the SDK
     *
     * @param array $options Configuration options:
     *   - api_key: (string, required) Your Mbuzz API key
     *   - api_url: (string, optional) API base URL, default: https://mbuzz.co/api/v1
     *   - enabled: (bool, optional) Enable/disable tracking, default: true
     *   - debug: (bool, optional) Enable debug logging, default: false
     *   - timeout: (int, optional) HTTP timeout in seconds, default: 5
     *   - skip_paths: (array, optional) Additional paths to skip
     *   - skip_extensions: (array, optional) Additional extensions to skip
     */
    public static function init(array $options): void
    {
        $config = Config::getInstance();
        $config->init($options);

        self::$client = new Client($config);
    }

    /**
     * Initialize context from request (call early in request lifecycle)
     * This handles cookie reading/writing and session creation.
     */
    public static function initFromRequest(): void
    {
        self::ensureInitialized();
        self::$client->initFromRequest();
    }

    /**
     * Track an event
     *
     * @param string $eventType Event name (e.g., 'page_view', 'add_to_cart')
     * @param array $properties Custom event properties
     * @return array|false TrackResult with event_id on success, false on failure
     */
    public static function event(string $eventType, array $properties = []): array|false
    {
        self::ensureInitialized();
        return self::$client->track($eventType, $properties);
    }

    /**
     * Track a conversion
     *
     * @param string $conversionType Conversion name (e.g., 'purchase', 'signup')
     * @param array $options Conversion options:
     *   - revenue: (float, optional) Conversion value
     *   - currency: (string, optional) Currency code, default: USD
     *   - user_id: (string, optional) User ID
     *   - event_id: (string, optional) Associated event ID
     *   - is_acquisition: (bool, optional) Mark as acquisition conversion
     *   - inherit_acquisition: (bool, optional) Inherit attribution from acquisition
     *   - properties: (array, optional) Custom properties
     * @return array|false ConversionResult on success, false on failure
     */
    public static function conversion(string $conversionType, array $options = []): array|false
    {
        self::ensureInitialized();
        return self::$client->conversion($conversionType, $options);
    }

    /**
     * Identify a user (link visitor to known user)
     *
     * @param string|int $userId Your application's user ID
     * @param array $traits User attributes (email, name, plan, etc.)
     * @return bool True on success
     */
    public static function identify(string|int $userId, array $traits = []): bool
    {
        self::ensureInitialized();
        return self::$client->identify((string) $userId, $traits);
    }

    /**
     * Get current visitor ID
     */
    public static function visitorId(): ?string
    {
        $context = Context::getInstance();
        return $context->isInitialized() ? $context->getVisitorId() : null;
    }

    /**
     * Get current session ID
     */
    public static function sessionId(): ?string
    {
        $context = Context::getInstance();
        return $context->isInitialized() ? $context->getSessionId() : null;
    }

    /**
     * Get current user ID (if set via identify)
     */
    public static function userId(): ?string
    {
        $context = Context::getInstance();
        return $context->isInitialized() ? $context->getUserId() : null;
    }

    /**
     * Reset SDK state (for testing or request cleanup)
     */
    public static function reset(): void
    {
        Config::reset();
        Context::reset();
        self::$client = null;
    }

    /**
     * Inject PSR-18 HTTP client
     */
    public static function setHttpClient(
        \Psr\Http\Client\ClientInterface $client,
        \Psr\Http\Message\RequestFactoryInterface $requestFactory,
        \Psr\Http\Message\StreamFactoryInterface $streamFactory
    ): void {
        self::ensureInitialized();
        self::$client->setHttpClient($client, $requestFactory, $streamFactory);
    }

    private static function ensureInitialized(): void
    {
        if (self::$client === null) {
            throw new \RuntimeException('Mbuzz::init() must be called before using the SDK');
        }
    }
}
```

### 7. Client Orchestrator (`Client.php`)

```php
<?php

declare(strict_types=1);

namespace Mbuzz;

use Mbuzz\Request\TrackRequest;
use Mbuzz\Request\IdentifyRequest;
use Mbuzz\Request\ConversionRequest;
use Mbuzz\Request\SessionRequest;

final class Client
{
    private Config $config;
    private Api $api;
    private CookieManager $cookies;
    private Context $context;

    public function __construct(Config $config)
    {
        $this->config = $config;
        $this->api = new Api($config);
        $this->cookies = new CookieManager();
        $this->context = Context::getInstance();
    }

    public function setHttpClient(
        \Psr\Http\Client\ClientInterface $client,
        \Psr\Http\Message\RequestFactoryInterface $requestFactory,
        \Psr\Http\Message\StreamFactoryInterface $streamFactory
    ): void {
        $this->api->setHttpClient($client, $requestFactory, $streamFactory);
    }

    /**
     * Initialize context from request (cookies, session creation)
     */
    public function initFromRequest(): void
    {
        if (!$this->config->isEnabled()) {
            return;
        }

        // Skip tracking paths
        $path = $_SERVER['REQUEST_URI'] ?? '/';
        $path = parse_url($path, PHP_URL_PATH) ?: '/';
        if ($this->config->shouldSkipPath($path)) {
            return;
        }

        // Initialize context from cookies
        $this->context->initialize($this->cookies);

        // Create session if new
        if ($this->context->isNewSession()) {
            $this->createSessionAsync();
        }
    }

    public function track(string $eventType, array $properties = []): array|false
    {
        if (!$this->config->isEnabled()) {
            return false;
        }

        // Auto-initialize context if not done
        if (!$this->context->isInitialized()) {
            $this->context->initialize($this->cookies);
        }

        $request = new TrackRequest(
            eventType: $eventType,
            visitorId: $this->context->getVisitorId(),
            sessionId: $this->context->getSessionId(),
            userId: $this->context->getUserId(),
            properties: $this->context->enrichProperties($properties)
        );

        return $request->send($this->api);
    }

    public function conversion(string $conversionType, array $options = []): array|false
    {
        if (!$this->config->isEnabled()) {
            return false;
        }

        // Auto-initialize context if not done
        if (!$this->context->isInitialized()) {
            $this->context->initialize($this->cookies);
        }

        $request = new ConversionRequest(
            conversionType: $conversionType,
            visitorId: $options['visitor_id'] ?? $this->context->getVisitorId(),
            userId: $options['user_id'] ?? $this->context->getUserId(),
            eventId: $options['event_id'] ?? null,
            revenue: $options['revenue'] ?? null,
            currency: $options['currency'] ?? 'USD',
            isAcquisition: $options['is_acquisition'] ?? false,
            inheritAcquisition: $options['inherit_acquisition'] ?? false,
            properties: $options['properties'] ?? []
        );

        return $request->send($this->api);
    }

    public function identify(string $userId, array $traits = []): bool
    {
        if (!$this->config->isEnabled()) {
            return false;
        }

        // Auto-initialize context if not done
        if (!$this->context->isInitialized()) {
            $this->context->initialize($this->cookies);
        }

        // Store user ID in context
        $this->context->setUserId($userId);

        $request = new IdentifyRequest(
            userId: $userId,
            visitorId: $this->context->getVisitorId(),
            traits: $traits
        );

        return $request->send($this->api);
    }

    /**
     * Create session asynchronously (fire and forget)
     */
    private function createSessionAsync(): void
    {
        $request = new SessionRequest(
            visitorId: $this->context->getVisitorId(),
            sessionId: $this->context->getSessionId(),
            url: $this->context->getUrl(),
            referrer: $this->context->getReferrer()
        );

        // Fire and forget - don't block the request
        $request->send($this->api);
    }
}
```

---

## Request Classes

### TrackRequest

```php
<?php

declare(strict_types=1);

namespace Mbuzz\Request;

use Mbuzz\Api;

final class TrackRequest
{
    public function __construct(
        private string $eventType,
        private ?string $visitorId = null,
        private ?string $sessionId = null,
        private ?string $userId = null,
        private array $properties = []
    ) {}

    public function send(Api $api): array|false
    {
        if (empty($this->eventType)) {
            return false;
        }

        if ($this->visitorId === null && $this->userId === null) {
            return false;
        }

        $payload = [
            'events' => [[
                'event_type' => $this->eventType,
                'visitor_id' => $this->visitorId,
                'session_id' => $this->sessionId,
                'user_id' => $this->userId,
                'properties' => $this->properties,
                'timestamp' => $this->isoNow(),
            ]]
        ];

        $response = $api->postWithResponse('/events', $payload);

        if ($response === null || empty($response['events'])) {
            return false;
        }

        $event = $response['events'][0];
        return [
            'success' => true,
            'event_id' => $event['id'] ?? null,
            'event_type' => $this->eventType,
            'visitor_id' => $this->visitorId,
            'session_id' => $this->sessionId,
        ];
    }

    private function isoNow(): string
    {
        return (new \DateTimeImmutable('now', new \DateTimeZone('UTC')))->format('c');
    }
}
```

### IdentifyRequest

```php
<?php

declare(strict_types=1);

namespace Mbuzz\Request;

use Mbuzz\Api;

final class IdentifyRequest
{
    public function __construct(
        private string $userId,
        private ?string $visitorId = null,
        private array $traits = []
    ) {}

    public function send(Api $api): bool
    {
        if (empty($this->userId)) {
            return false;
        }

        $payload = [
            'user_id' => $this->userId,
            'visitor_id' => $this->visitorId,
            'traits' => $this->traits,
        ];

        return $api->post('/identify', $payload);
    }
}
```

### ConversionRequest

```php
<?php

declare(strict_types=1);

namespace Mbuzz\Request;

use Mbuzz\Api;

final class ConversionRequest
{
    public function __construct(
        private string $conversionType,
        private ?string $visitorId = null,
        private ?string $userId = null,
        private ?string $eventId = null,
        private ?float $revenue = null,
        private string $currency = 'USD',
        private bool $isAcquisition = false,
        private bool $inheritAcquisition = false,
        private array $properties = []
    ) {}

    public function send(Api $api): array|false
    {
        if (empty($this->conversionType)) {
            return false;
        }

        // Must have at least one identifier
        if ($this->visitorId === null && $this->userId === null && $this->eventId === null) {
            return false;
        }

        $payload = [
            'conversion' => [
                'conversion_type' => $this->conversionType,
                'visitor_id' => $this->visitorId,
                'user_id' => $this->userId,
                'event_id' => $this->eventId,
                'revenue' => $this->revenue,
                'currency' => $this->currency,
                'is_acquisition' => $this->isAcquisition,
                'inherit_acquisition' => $this->inheritAcquisition,
                'properties' => $this->properties,
                'timestamp' => $this->isoNow(),
            ]
        ];

        $response = $api->postWithResponse('/conversions', $payload);

        if ($response === null) {
            return false;
        }

        return [
            'success' => true,
            'conversion_id' => $response['conversion']['id'] ?? null,
            'attribution' => $response['attribution'] ?? null,
        ];
    }

    private function isoNow(): string
    {
        return (new \DateTimeImmutable('now', new \DateTimeZone('UTC')))->format('c');
    }
}
```

### SessionRequest

```php
<?php

declare(strict_types=1);

namespace Mbuzz\Request;

use Mbuzz\Api;

final class SessionRequest
{
    public function __construct(
        private string $visitorId,
        private string $sessionId,
        private ?string $url = null,
        private ?string $referrer = null
    ) {}

    public function send(Api $api): bool
    {
        if (empty($this->visitorId) || empty($this->sessionId)) {
            return false;
        }

        // URL is required for session creation
        if ($this->url === null) {
            return false;
        }

        $payload = [
            'session' => [
                'visitor_id' => $this->visitorId,
                'session_id' => $this->sessionId,
                'url' => $this->url,
                'referrer' => $this->referrer,
                'started_at' => $this->isoNow(),
            ]
        ];

        return $api->post('/sessions', $payload);
    }

    private function isoNow(): string
    {
        return (new \DateTimeImmutable('now', new \DateTimeZone('UTC')))->format('c');
    }
}
```

---

## Framework Integrations

### Native PHP Middleware

For plain PHP applications without a framework.

```php
<?php

declare(strict_types=1);

namespace Mbuzz\Middleware;

use Mbuzz\Mbuzz;

final class NativeMiddleware
{
    /**
     * Initialize tracking at the beginning of a request
     * Call this early in your bootstrap, before any output
     */
    public static function handle(): void
    {
        Mbuzz::initFromRequest();
    }
}
```

**Usage:**

```php
<?php
// index.php or bootstrap.php

require 'vendor/autoload.php';

use Mbuzz\Mbuzz;
use Mbuzz\Middleware\NativeMiddleware;

// Initialize SDK
Mbuzz::init([
    'api_key' => $_ENV['MBUZZ_API_KEY'],
]);

// Initialize from request (reads cookies, creates session if needed)
NativeMiddleware::handle();

// Your application code...
Mbuzz::event('page_view');
```

### PSR-15 Middleware

For frameworks supporting PSR-15 (Slim, Mezzio, etc.).

```php
<?php

declare(strict_types=1);

namespace Mbuzz\Middleware;

use Mbuzz\Mbuzz;
use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\MiddlewareInterface;
use Psr\Http\Server\RequestHandlerInterface;

final class TrackingMiddleware implements MiddlewareInterface
{
    public function process(
        ServerRequestInterface $request,
        RequestHandlerInterface $handler
    ): ResponseInterface {
        // Initialize from request
        Mbuzz::initFromRequest();

        // Continue to next middleware
        return $handler->handle($request);
    }
}
```

**Usage with Slim:**

```php
<?php
// app.php

use Slim\Factory\AppFactory;
use Mbuzz\Mbuzz;
use Mbuzz\Middleware\TrackingMiddleware;

$app = AppFactory::create();

// Initialize SDK
Mbuzz::init(['api_key' => $_ENV['MBUZZ_API_KEY']]);

// Add middleware
$app->add(new TrackingMiddleware());

$app->run();
```

### Laravel Service Provider

```php
<?php

declare(strict_types=1);

namespace Mbuzz\Adapter;

use Illuminate\Support\ServiceProvider;
use Mbuzz\Mbuzz;

class LaravelServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        // Register config
        $this->mergeConfigFrom(__DIR__ . '/../../config/mbuzz.php', 'mbuzz');
    }

    public function boot(): void
    {
        // Publish config
        $this->publishes([
            __DIR__ . '/../../config/mbuzz.php' => config_path('mbuzz.php'),
        ], 'mbuzz-config');

        // Initialize SDK
        if (config('mbuzz.enabled', true)) {
            Mbuzz::init([
                'api_key' => config('mbuzz.api_key'),
                'api_url' => config('mbuzz.api_url', 'https://mbuzz.co/api/v1'),
                'debug' => config('mbuzz.debug', false),
                'skip_paths' => config('mbuzz.skip_paths', []),
            ]);
        }
    }
}
```

### Laravel Middleware

```php
<?php

declare(strict_types=1);

namespace Mbuzz\Adapter;

use Closure;
use Illuminate\Http\Request;
use Mbuzz\Mbuzz;

class LaravelMiddleware
{
    public function handle(Request $request, Closure $next)
    {
        Mbuzz::initFromRequest();

        return $next($request);
    }
}
```

**Laravel Installation:**

```php
// config/app.php
'providers' => [
    // ...
    Mbuzz\Adapter\LaravelServiceProvider::class,
],

// app/Http/Kernel.php
protected $middleware = [
    // ...
    \Mbuzz\Adapter\LaravelMiddleware::class,
];
```

### Symfony Bundle (Future)

```php
<?php

declare(strict_types=1);

namespace Mbuzz\Adapter;

use Symfony\Component\HttpKernel\Bundle\Bundle;

class MbuzzBundle extends Bundle
{
    // Symfony bundle implementation
}
```

---

## Package Configuration

### composer.json

```json
{
    "name": "mbuzz/mbuzz-php",
    "description": "Multi-touch attribution SDK for PHP - framework agnostic",
    "type": "library",
    "license": "MIT",
    "keywords": ["analytics", "attribution", "marketing", "tracking", "mbuzz"],
    "homepage": "https://mbuzz.co",
    "authors": [
        {
            "name": "Mbuzz",
            "email": "support@mbuzz.co"
        }
    ],
    "require": {
        "php": ">=8.1",
        "ext-curl": "*",
        "ext-json": "*"
    },
    "require-dev": {
        "phpunit/phpunit": "^10.0",
        "phpstan/phpstan": "^1.10",
        "squizlabs/php_codesniffer": "^3.7",
        "psr/http-client": "^1.0",
        "psr/http-factory": "^1.0",
        "psr/http-message": "^2.0",
        "psr/http-server-middleware": "^1.0",
        "guzzlehttp/guzzle": "^7.0"
    },
    "suggest": {
        "psr/http-client-implementation": "For using a PSR-18 HTTP client instead of cURL",
        "psr/http-server-middleware": "For PSR-15 middleware support",
        "guzzlehttp/guzzle": "PSR-18 compatible HTTP client"
    },
    "autoload": {
        "psr-4": {
            "Mbuzz\\": "src/Mbuzz/"
        }
    },
    "autoload-dev": {
        "psr-4": {
            "Mbuzz\\Tests\\": "tests/"
        }
    },
    "extra": {
        "laravel": {
            "providers": [
                "Mbuzz\\Adapter\\LaravelServiceProvider"
            ]
        }
    },
    "config": {
        "sort-packages": true
    }
}
```

---

## Cookie Constants

```php
// Cookie names (must match other SDKs)
VISITOR_COOKIE = "_mbuzz_vid"
SESSION_COOKIE = "_mbuzz_sid"

// Cookie expiry (must match other SDKs)
VISITOR_MAX_AGE = 63072000  // 2 years in seconds
SESSION_MAX_AGE = 1800      // 30 minutes in seconds

// Cookie attributes
HttpOnly = true
SameSite = "Lax"
Secure = auto-detected (true if HTTPS)
Path = "/"
```

---

## Testing

### Unit Tests

```php
<?php

declare(strict_types=1);

namespace Mbuzz\Tests\Unit;

use Mbuzz\Config;
use PHPUnit\Framework\TestCase;

class ConfigTest extends TestCase
{
    protected function tearDown(): void
    {
        Config::reset();
    }

    public function testInitRequiresApiKey(): void
    {
        $this->expectException(\InvalidArgumentException::class);

        Config::getInstance()->init([]);
    }

    public function testInitSetsApiKey(): void
    {
        $config = Config::getInstance();
        $config->init(['api_key' => 'sk_test_abc123']);

        $this->assertEquals('sk_test_abc123', $config->getApiKey());
        $this->assertTrue($config->isTestKey());
    }

    public function testShouldSkipPath(): void
    {
        $config = Config::getInstance();
        $config->init(['api_key' => 'sk_test_abc123']);

        $this->assertTrue($config->shouldSkipPath('/health'));
        $this->assertTrue($config->shouldSkipPath('/favicon.ico'));
        $this->assertTrue($config->shouldSkipPath('/assets/main.js'));
        $this->assertFalse($config->shouldSkipPath('/checkout'));
    }
}
```

### Integration Tests

Add PHP test app to SDK integration tests (port 4004).

```
sdk_integration_tests/apps/mbuzz_php_testapp/
├── composer.json
├── public/
│   └── index.php
└── views/
    └── index.php
```

---

## Implementation Checklist

### Phase 1: Core Infrastructure

- [ ] Create `mbuzz-php` repository
- [ ] Set up composer.json
- [ ] Implement `Config.php`
- [ ] Implement `IdGenerator.php`
- [ ] Implement `Api.php` (cURL fallback)
- [ ] Add PSR-18 client support
- [ ] Add unit tests

### Phase 2: Request Handling

- [ ] Implement `CookieManager.php`
- [ ] Implement `Context.php`
- [ ] Implement `Request/TrackRequest.php`
- [ ] Implement `Request/IdentifyRequest.php`
- [ ] Implement `Request/ConversionRequest.php`
- [ ] Implement `Request/SessionRequest.php`
- [ ] Add unit tests

### Phase 3: Public API

- [ ] Implement `Client.php`
- [ ] Implement `Mbuzz.php` (static facade)
- [ ] Add integration tests

### Phase 4: Middleware

- [ ] Implement `Middleware/NativeMiddleware.php`
- [ ] Implement `Middleware/TrackingMiddleware.php` (PSR-15)
- [ ] Add middleware tests

### Phase 5: Framework Adapters

- [ ] Implement Laravel ServiceProvider
- [ ] Implement Laravel Middleware
- [ ] Add Laravel config file
- [ ] Test with Laravel app
- [ ] (Future) Symfony Bundle
- [ ] (Future) Slim adapter

### Phase 6: Documentation

- [ ] Write README.md
- [ ] Add CHANGELOG.md
- [ ] Add inline PHPDoc comments
- [ ] Create examples directory

### Phase 7: Release

- [ ] Publish to Packagist
- [ ] Update sdk_registry.yml (status: live)
- [ ] Update sdk_registry.md
- [ ] Add to docs code tabs
- [ ] Create PHP test app for integration tests

---

## Sources

- [PSR-18: HTTP Client](https://www.php-fig.org/psr/psr-18/)
- [Bring Your Own HTTP Client - SensioLabs](https://sensiolabs.com/blog/2025/bring-your-own-http-client)
- [PSR-15: HTTP Server Middleware](https://www.php-fig.org/psr/psr-15/)
- [dflydev/fig-cookies - PSR-7 Cookies](https://github.com/dflydev/dflydev-fig-cookies)
- [Segment PHP SDK](https://github.com/segmentio/analytics-php)
- [Mixpanel PHP SDK](https://docs.mixpanel.com/docs/tracking-methods/sdks/php)
- [PHP setcookie Manual](https://www.php.net/manual/en/function.setcookie.php)
- [PSR-7 and Session Cookies](https://paul-m-jones.com/post/2016/04/12/psr-7-and-session-cookies/)
