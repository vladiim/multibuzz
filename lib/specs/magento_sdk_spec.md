# Magento 2 SDK Specification

**Status**: Research Complete - Ready for Implementation
**Last Updated**: 2025-11-28
**Target Platforms**: Magento 2.4.x, Adobe Commerce

---

## Overview

Server-side multi-touch attribution tracking extension for Magento 2. Tracks e-commerce events (page views, add to cart, checkout, purchase, customer registration) and sends them to the Mbuzz API for attribution analysis.

### Why Server-Side?

1. **Ad-blocker resistant** - Server-side tracking cannot be blocked by browser extensions
2. **Closed browser problem** - Client-side JS fails when users close browser before success page loads
3. **Data accuracy** - Server has authoritative order data (payment confirmed, not just attempted)
4. **Performance** - No JavaScript overhead on storefront

### Key Metrics

Based on [elgentos/magento2-serversideanalytics](https://github.com/elgentos/magento2-serversideanalytics), client-side tracking misses 10-15% of purchases due to users closing browsers before the success page loads.

---

## Module Structure

```
app/code/Mbuzz/Tracking/
├── registration.php                    # Magento module registration
├── composer.json                       # Composer package definition
├── LICENSE                             # MIT License
├── README.md                           # Installation & usage docs
│
├── etc/
│   ├── module.xml                      # Module declaration & dependencies
│   ├── config.xml                      # Default configuration values
│   ├── di.xml                          # Dependency injection configuration
│   ├── crontab.xml                     # Cron jobs (optional: batch sending)
│   ├── adminhtml/
│   │   ├── system.xml                  # Admin configuration UI
│   │   └── routes.xml                  # Admin routes (if needed)
│   ├── frontend/
│   │   ├── events.xml                  # Frontend event observers
│   │   └── routes.xml                  # Frontend routes (if needed)
│   └── events.xml                      # Global event observers
│
├── Api/
│   ├── ClientInterface.php             # API client interface
│   └── Data/
│       └── EventInterface.php          # Event data interface
│
├── Model/
│   ├── Config.php                      # Configuration provider
│   ├── Client.php                      # HTTP client implementation
│   ├── EventBuilder.php                # Builds event payloads
│   ├── VisitorManager.php              # Visitor/session cookie management
│   └── Queue/
│       └── EventPublisher.php          # Message queue publisher (optional)
│
├── Observer/
│   ├── PageViewObserver.php            # Track page views
│   ├── ProductViewObserver.php         # Track product views
│   ├── AddToCartObserver.php           # Track add_to_cart events
│   ├── RemoveFromCartObserver.php      # Track remove_from_cart events
│   ├── CheckoutStartObserver.php       # Track checkout_started
│   ├── OrderPlaceObserver.php          # Track purchase (server-side)
│   ├── OrderRefundObserver.php         # Track refunds
│   ├── CustomerRegisterObserver.php    # Track signup
│   └── CustomerLoginObserver.php       # Track login / identify
│
├── Plugin/
│   ├── VisitorCookiePlugin.php         # Initialize visitor cookies
│   └── SessionUtmPlugin.php            # Capture UTM on session start
│
├── Helper/
│   └── Data.php                        # Utility functions
│
├── Console/
│   └── Command/
│       └── TestConnectionCommand.php   # CLI: bin/magento mbuzz:test
│
├── Block/
│   └── Adminhtml/
│       └── System/
│           └── Config/
│               └── TestConnection.php  # Admin "Test Connection" button
│
├── Controller/
│   └── Adminhtml/
│       └── Config/
│           └── Test.php                # AJAX endpoint for connection test
│
├── Setup/
│   └── Patch/
│       └── Data/
│           └── CreateDefaultConfig.php # Default configuration setup
│
├── Test/
│   ├── Unit/
│   │   ├── Model/
│   │   │   ├── ClientTest.php
│   │   │   ├── ConfigTest.php
│   │   │   └── VisitorManagerTest.php
│   │   └── Observer/
│   │       └── OrderPlaceObserverTest.php
│   └── Integration/
│       └── Observer/
│           └── OrderPlaceObserverTest.php
│
└── view/
    ├── adminhtml/
    │   ├── layout/
    │   │   └── adminhtml_system_config_edit.xml
    │   └── templates/
    │       └── system/
    │           └── config/
    │               └── test_connection.phtml
    └── frontend/
        └── layout/
            └── default.xml             # Initialize cookies on all pages
```

---

## Configuration

### Admin UI Configuration

**Location**: Stores > Configuration > Sales > Mbuzz Tracking

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| Enable Tracking | Yes/No | No | Master switch for all tracking |
| API Key | Password | - | Mbuzz API key (sk_live_* or sk_test_*) |
| API URL | Text | https://mbuzz.co/api/v1 | API endpoint (for self-hosted) |
| Debug Mode | Yes/No | No | Log all API requests/responses |
| Track Page Views | Yes/No | Yes | Track page_view events |
| Track Add to Cart | Yes/No | Yes | Track add_to_cart events |
| Track Purchases | Yes/No | Yes | Track purchase events |
| Track Customer Registration | Yes/No | Yes | Track signup events |
| Use Async Queue | Yes/No | No | Use message queue for sending |

### Configuration XML

```xml
<!-- etc/config.xml -->
<?xml version="1.0"?>
<config xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xsi:noNamespaceSchemaLocation="urn:magento:module:Magento_Store:etc/config.xsd">
    <default>
        <mbuzz>
            <general>
                <enabled>0</enabled>
                <api_key backend_model="Magento\Config\Model\Config\Backend\Encrypted"/>
                <api_url>https://mbuzz.co/api/v1</api_url>
                <debug>0</debug>
            </general>
            <tracking>
                <page_views>1</page_views>
                <add_to_cart>1</add_to_cart>
                <purchases>1</purchases>
                <customer_registration>1</customer_registration>
            </tracking>
            <advanced>
                <use_queue>0</use_queue>
                <batch_size>10</batch_size>
            </advanced>
        </mbuzz>
    </default>
</config>
```

### System Configuration UI

```xml
<!-- etc/adminhtml/system.xml -->
<?xml version="1.0"?>
<config xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xsi:noNamespaceSchemaLocation="urn:magento:module:Magento_Config:etc/system_file.xsd">
    <system>
        <tab id="mbuzz" translate="label" sortOrder="500">
            <label>Mbuzz</label>
        </tab>
        <section id="mbuzz" translate="label" type="text" sortOrder="10"
                 showInDefault="1" showInWebsite="1" showInStore="1">
            <label>Attribution Tracking</label>
            <tab>mbuzz</tab>
            <resource>Mbuzz_Tracking::config</resource>

            <group id="general" translate="label" type="text" sortOrder="10"
                   showInDefault="1" showInWebsite="1" showInStore="1">
                <label>General Settings</label>

                <field id="enabled" translate="label comment" type="select" sortOrder="10"
                       showInDefault="1" showInWebsite="1" showInStore="1">
                    <label>Enable Tracking</label>
                    <source_model>Magento\Config\Model\Config\Source\Yesno</source_model>
                    <comment>Enable or disable all Mbuzz tracking</comment>
                </field>

                <field id="api_key" translate="label comment" type="obscure" sortOrder="20"
                       showInDefault="1" showInWebsite="1" showInStore="0">
                    <label>API Key</label>
                    <backend_model>Magento\Config\Model\Config\Backend\Encrypted</backend_model>
                    <comment><![CDATA[
                        Enter your Mbuzz API key.
                        Use <code>sk_test_*</code> for testing, <code>sk_live_*</code> for production.
                        Get your key at <a href="https://mbuzz.co/dashboard/api-keys" target="_blank">mbuzz.co/dashboard</a>
                    ]]></comment>
                </field>

                <field id="test_connection" translate="label" type="button" sortOrder="25"
                       showInDefault="1" showInWebsite="1" showInStore="0">
                    <label>Test Connection</label>
                    <frontend_model>Mbuzz\Tracking\Block\Adminhtml\System\Config\TestConnection</frontend_model>
                </field>

                <field id="api_url" translate="label comment" type="text" sortOrder="30"
                       showInDefault="1" showInWebsite="0" showInStore="0">
                    <label>API URL</label>
                    <comment>Only change for self-hosted installations</comment>
                </field>

                <field id="debug" translate="label comment" type="select" sortOrder="40"
                       showInDefault="1" showInWebsite="1" showInStore="1">
                    <label>Debug Mode</label>
                    <source_model>Magento\Config\Model\Config\Source\Yesno</source_model>
                    <comment>Log all API requests to var/log/mbuzz.log</comment>
                </field>
            </group>

            <group id="tracking" translate="label" type="text" sortOrder="20"
                   showInDefault="1" showInWebsite="1" showInStore="1">
                <label>Event Tracking</label>

                <field id="page_views" translate="label" type="select" sortOrder="10"
                       showInDefault="1" showInWebsite="1" showInStore="1">
                    <label>Track Page Views</label>
                    <source_model>Magento\Config\Model\Config\Source\Yesno</source_model>
                </field>

                <field id="add_to_cart" translate="label" type="select" sortOrder="20"
                       showInDefault="1" showInWebsite="1" showInStore="1">
                    <label>Track Add to Cart</label>
                    <source_model>Magento\Config\Model\Config\Source\Yesno</source_model>
                </field>

                <field id="purchases" translate="label" type="select" sortOrder="30"
                       showInDefault="1" showInWebsite="1" showInStore="1">
                    <label>Track Purchases</label>
                    <source_model>Magento\Config\Model\Config\Source\Yesno</source_model>
                </field>

                <field id="customer_registration" translate="label" type="select" sortOrder="40"
                       showInDefault="1" showInWebsite="1" showInStore="1">
                    <label>Track Customer Registration</label>
                    <source_model>Magento\Config\Model\Config\Source\Yesno</source_model>
                </field>
            </group>

            <group id="advanced" translate="label" type="text" sortOrder="30"
                   showInDefault="1" showInWebsite="0" showInStore="0">
                <label>Advanced Settings</label>

                <field id="use_queue" translate="label comment" type="select" sortOrder="10"
                       showInDefault="1" showInWebsite="0" showInStore="0">
                    <label>Use Message Queue</label>
                    <source_model>Magento\Config\Model\Config\Source\Yesno</source_model>
                    <comment>Send events asynchronously via RabbitMQ (recommended for high-traffic stores)</comment>
                </field>
            </group>
        </section>
    </system>
</config>
```

---

## Core Components

### 1. Configuration Provider

```php
<?php
declare(strict_types=1);

namespace Mbuzz\Tracking\Model;

use Magento\Framework\App\Config\ScopeConfigInterface;
use Magento\Store\Model\ScopeInterface;
use Magento\Framework\Encryption\EncryptorInterface;

class Config
{
    private const XML_PATH_ENABLED = 'mbuzz/general/enabled';
    private const XML_PATH_API_KEY = 'mbuzz/general/api_key';
    private const XML_PATH_API_URL = 'mbuzz/general/api_url';
    private const XML_PATH_DEBUG = 'mbuzz/general/debug';
    private const XML_PATH_TRACK_PAGE_VIEWS = 'mbuzz/tracking/page_views';
    private const XML_PATH_TRACK_ADD_TO_CART = 'mbuzz/tracking/add_to_cart';
    private const XML_PATH_TRACK_PURCHASES = 'mbuzz/tracking/purchases';
    private const XML_PATH_TRACK_REGISTRATION = 'mbuzz/tracking/customer_registration';
    private const XML_PATH_USE_QUEUE = 'mbuzz/advanced/use_queue';

    public function __construct(
        private ScopeConfigInterface $scopeConfig,
        private EncryptorInterface $encryptor
    ) {}

    public function isEnabled(?int $storeId = null): bool
    {
        return $this->scopeConfig->isSetFlag(
            self::XML_PATH_ENABLED,
            ScopeInterface::SCOPE_STORE,
            $storeId
        );
    }

    public function getApiKey(?int $storeId = null): string
    {
        $encrypted = $this->scopeConfig->getValue(
            self::XML_PATH_API_KEY,
            ScopeInterface::SCOPE_STORE,
            $storeId
        );

        return $encrypted ? $this->encryptor->decrypt($encrypted) : '';
    }

    public function getApiUrl(): string
    {
        return $this->scopeConfig->getValue(self::XML_PATH_API_URL)
            ?: 'https://mbuzz.co/api/v1';
    }

    public function isDebugEnabled(?int $storeId = null): bool
    {
        return $this->scopeConfig->isSetFlag(
            self::XML_PATH_DEBUG,
            ScopeInterface::SCOPE_STORE,
            $storeId
        );
    }

    public function shouldTrackPageViews(?int $storeId = null): bool
    {
        return $this->isEnabled($storeId) && $this->scopeConfig->isSetFlag(
            self::XML_PATH_TRACK_PAGE_VIEWS,
            ScopeInterface::SCOPE_STORE,
            $storeId
        );
    }

    public function shouldTrackAddToCart(?int $storeId = null): bool
    {
        return $this->isEnabled($storeId) && $this->scopeConfig->isSetFlag(
            self::XML_PATH_TRACK_ADD_TO_CART,
            ScopeInterface::SCOPE_STORE,
            $storeId
        );
    }

    public function shouldTrackPurchases(?int $storeId = null): bool
    {
        return $this->isEnabled($storeId) && $this->scopeConfig->isSetFlag(
            self::XML_PATH_TRACK_PURCHASES,
            ScopeInterface::SCOPE_STORE,
            $storeId
        );
    }

    public function shouldTrackRegistration(?int $storeId = null): bool
    {
        return $this->isEnabled($storeId) && $this->scopeConfig->isSetFlag(
            self::XML_PATH_TRACK_REGISTRATION,
            ScopeInterface::SCOPE_STORE,
            $storeId
        );
    }

    public function useQueue(): bool
    {
        return $this->scopeConfig->isSetFlag(self::XML_PATH_USE_QUEUE);
    }

    public function isTestKey(): bool
    {
        return str_starts_with($this->getApiKey(), 'sk_test_');
    }
}
```

### 2. API Client

```php
<?php
declare(strict_types=1);

namespace Mbuzz\Tracking\Model;

use Mbuzz\Tracking\Api\ClientInterface;
use Magento\Framework\HTTP\Client\Curl;
use Psr\Log\LoggerInterface;

class Client implements ClientInterface
{
    private const USER_AGENT = 'mbuzz-magento/0.1.0';
    private const TIMEOUT = 5; // seconds

    public function __construct(
        private Curl $curl,
        private Config $config,
        private LoggerInterface $logger
    ) {}

    public function track(array $event): bool
    {
        if (!$this->config->isEnabled()) {
            return false;
        }

        $apiKey = $this->config->getApiKey();
        if (empty($apiKey)) {
            $this->log('API key not configured');
            return false;
        }

        return $this->sendRequest('/events', $event);
    }

    public function trackBatch(array $events): array
    {
        if (!$this->config->isEnabled() || empty($events)) {
            return ['accepted' => 0, 'rejected' => []];
        }

        $response = $this->sendRequest('/events', ['events' => $events], true);

        return $response ?: ['accepted' => 0, 'rejected' => $events];
    }

    public function validate(): array
    {
        $apiKey = $this->config->getApiKey();
        if (empty($apiKey)) {
            return ['valid' => false, 'error' => 'API key not configured'];
        }

        $response = $this->sendRequest('/validate', [], true, 'GET');

        return $response ?: ['valid' => false, 'error' => 'Connection failed'];
    }

    private function sendRequest(
        string $endpoint,
        array $data,
        bool $returnResponse = false,
        string $method = 'POST'
    ): mixed {
        $url = rtrim($this->config->getApiUrl(), '/') . $endpoint;

        $this->curl->setOption(CURLOPT_TIMEOUT, self::TIMEOUT);
        $this->curl->setOption(CURLOPT_CONNECTTIMEOUT, self::TIMEOUT);
        $this->curl->addHeader('Authorization', 'Bearer ' . $this->config->getApiKey());
        $this->curl->addHeader('Content-Type', 'application/json');
        $this->curl->addHeader('User-Agent', self::USER_AGENT);

        try {
            $this->log("Request: $method $url", $data);

            if ($method === 'GET') {
                $this->curl->get($url);
            } else {
                $this->curl->post($url, json_encode($data));
            }

            $status = $this->curl->getStatus();
            $body = $this->curl->getBody();
            $response = json_decode($body, true);

            $this->log("Response: $status", $response);

            if ($returnResponse) {
                return $response;
            }

            return $status >= 200 && $status < 300;

        } catch (\Exception $e) {
            $this->log("Error: " . $e->getMessage());
            return $returnResponse ? null : false;
        }
    }

    private function log(string $message, array $context = []): void
    {
        if ($this->config->isDebugEnabled()) {
            $this->logger->info('[Mbuzz] ' . $message, $context);
        }
    }
}
```

### 3. Visitor Manager

```php
<?php
declare(strict_types=1);

namespace Mbuzz\Tracking\Model;

use Magento\Framework\Stdlib\Cookie\CookieMetadataFactory;
use Magento\Framework\Stdlib\CookieManagerInterface;
use Magento\Framework\Session\SessionManagerInterface;

class VisitorManager
{
    private const VISITOR_COOKIE = '_mbuzz_vid';
    private const SESSION_COOKIE = '_mbuzz_sid';
    private const VISITOR_LIFETIME = 31536000; // 1 year in seconds
    private const SESSION_LIFETIME = 1800;     // 30 minutes in seconds

    private ?string $visitorId = null;
    private ?string $sessionId = null;

    public function __construct(
        private CookieManagerInterface $cookieManager,
        private CookieMetadataFactory $cookieMetadataFactory,
        private SessionManagerInterface $sessionManager
    ) {}

    public function getVisitorId(): string
    {
        if ($this->visitorId !== null) {
            return $this->visitorId;
        }

        $this->visitorId = $this->cookieManager->getCookie(self::VISITOR_COOKIE);

        if (empty($this->visitorId)) {
            $this->visitorId = $this->generateId();
            $this->setCookie(self::VISITOR_COOKIE, $this->visitorId, self::VISITOR_LIFETIME);
        }

        return $this->visitorId;
    }

    public function getSessionId(): string
    {
        if ($this->sessionId !== null) {
            return $this->sessionId;
        }

        $this->sessionId = $this->cookieManager->getCookie(self::SESSION_COOKIE);

        if (empty($this->sessionId)) {
            $this->sessionId = $this->generateId();
        }

        // Always refresh session cookie to extend timeout
        $this->setCookie(self::SESSION_COOKIE, $this->sessionId, self::SESSION_LIFETIME);

        return $this->sessionId;
    }

    public function isNewVisitor(): bool
    {
        return empty($this->cookieManager->getCookie(self::VISITOR_COOKIE));
    }

    public function isNewSession(): bool
    {
        return empty($this->cookieManager->getCookie(self::SESSION_COOKIE));
    }

    private function generateId(): string
    {
        return bin2hex(random_bytes(32)); // 64-character hex string
    }

    private function setCookie(string $name, string $value, int $duration): void
    {
        $metadata = $this->cookieMetadataFactory
            ->createPublicCookieMetadata()
            ->setDuration($duration)
            ->setPath('/')
            ->setHttpOnly(true)
            ->setSecure(true)
            ->setSameSite('Lax');

        $this->cookieManager->setPublicCookie($name, $value, $metadata);
    }
}
```

### 4. Event Builder

```php
<?php
declare(strict_types=1);

namespace Mbuzz\Tracking\Model;

use Magento\Framework\App\RequestInterface;
use Magento\Framework\UrlInterface;
use Magento\Customer\Model\Session as CustomerSession;

class EventBuilder
{
    private const UTM_PARAMS = [
        'utm_source',
        'utm_medium',
        'utm_campaign',
        'utm_content',
        'utm_term'
    ];

    public function __construct(
        private VisitorManager $visitorManager,
        private RequestInterface $request,
        private UrlInterface $urlBuilder,
        private CustomerSession $customerSession
    ) {}

    public function build(string $eventType, array $properties = []): array
    {
        $event = [
            'event_type' => $eventType,
            'visitor_id' => $this->visitorManager->getVisitorId(),
            'timestamp' => (new \DateTime('now', new \DateTimeZone('UTC')))->format('c'),
            'properties' => $this->enrichProperties($properties),
        ];

        // Add user_id if customer is logged in
        if ($this->customerSession->isLoggedIn()) {
            $event['user_id'] = (string) $this->customerSession->getCustomerId();
        }

        return $event;
    }

    public function buildPageView(string $url = null, string $referrer = null): array
    {
        return $this->build('page_view', [
            'url' => $url ?: $this->getCurrentUrl(),
            'referrer' => $referrer ?: $this->request->getServer('HTTP_REFERER'),
        ]);
    }

    public function buildAddToCart(
        string $productSku,
        string $productName,
        float $price,
        int $quantity,
        array $extra = []
    ): array {
        return $this->build('add_to_cart', array_merge([
            'product_sku' => $productSku,
            'product_name' => $productName,
            'price' => $price,
            'quantity' => $quantity,
            'currency' => $this->getCurrency(),
        ], $extra));
    }

    public function buildPurchase(
        string $orderId,
        float $revenue,
        string $currency,
        array $items,
        array $extra = []
    ): array {
        return $this->build('purchase', array_merge([
            'order_id' => $orderId,
            'revenue' => $revenue,
            'currency' => $currency,
            'items' => $items,
        ], $extra));
    }

    public function buildSignup(string $userId, array $traits = []): array
    {
        $event = $this->build('signup', $traits);
        $event['user_id'] = $userId;
        return $event;
    }

    private function enrichProperties(array $properties): array
    {
        // Add UTM parameters from current request
        $utm = $this->extractUtmParams();
        if (!empty($utm)) {
            $properties = array_merge($utm, $properties);
        }

        // Add URL if not present
        if (!isset($properties['url'])) {
            $properties['url'] = $this->getCurrentUrl();
        }

        // Add referrer if not present
        if (!isset($properties['referrer'])) {
            $referrer = $this->request->getServer('HTTP_REFERER');
            if ($referrer) {
                $properties['referrer'] = $referrer;
            }
        }

        return $properties;
    }

    private function extractUtmParams(): array
    {
        $utm = [];
        foreach (self::UTM_PARAMS as $param) {
            $value = $this->request->getParam($param);
            if ($value) {
                $utm[$param] = $value;
            }
        }
        return $utm;
    }

    private function getCurrentUrl(): string
    {
        return $this->urlBuilder->getCurrentUrl();
    }

    private function getCurrency(): string
    {
        // Will be injected via DI in actual implementation
        return 'USD';
    }
}
```

---

## Event Observers

### 1. Order Place Observer (Purchase Tracking)

**Event**: `sales_order_payment_pay`

This event fires after payment is confirmed, solving the "closed browser" problem.

```php
<?php
declare(strict_types=1);

namespace Mbuzz\Tracking\Observer;

use Magento\Framework\Event\Observer;
use Magento\Framework\Event\ObserverInterface;
use Magento\Sales\Model\Order;
use Mbuzz\Tracking\Model\Client;
use Mbuzz\Tracking\Model\Config;
use Mbuzz\Tracking\Model\EventBuilder;
use Mbuzz\Tracking\Model\VisitorManager;
use Psr\Log\LoggerInterface;

class OrderPlaceObserver implements ObserverInterface
{
    public function __construct(
        private Client $client,
        private Config $config,
        private EventBuilder $eventBuilder,
        private VisitorManager $visitorManager,
        private LoggerInterface $logger
    ) {}

    public function execute(Observer $observer): void
    {
        if (!$this->config->shouldTrackPurchases()) {
            return;
        }

        try {
            /** @var \Magento\Sales\Model\Order\Payment $payment */
            $payment = $observer->getEvent()->getPayment();
            /** @var Order $order */
            $order = $payment->getOrder();

            // Only track fully paid orders
            if ($order->getBaseTotalDue() > 0) {
                return;
            }

            $event = $this->eventBuilder->buildPurchase(
                $order->getIncrementId(),
                (float) $order->getGrandTotal(),
                $order->getOrderCurrencyCode(),
                $this->buildOrderItems($order),
                $this->buildOrderProperties($order)
            );

            // Override user_id with customer ID from order
            if ($order->getCustomerId()) {
                $event['user_id'] = (string) $order->getCustomerId();
            }

            $this->client->track($event);

        } catch (\Exception $e) {
            $this->logger->error('[Mbuzz] Order tracking failed: ' . $e->getMessage());
        }
    }

    private function buildOrderItems(Order $order): array
    {
        $items = [];

        foreach ($order->getAllVisibleItems() as $item) {
            $items[] = [
                'sku' => $item->getSku(),
                'name' => $item->getName(),
                'price' => (float) $item->getPrice(),
                'quantity' => (int) $item->getQtyOrdered(),
                'category' => $this->getProductCategory($item),
            ];
        }

        return $items;
    }

    private function buildOrderProperties(Order $order): array
    {
        $properties = [
            'payment_method' => $order->getPayment()->getMethod(),
            'shipping_method' => $order->getShippingMethod(),
            'item_count' => (int) $order->getTotalItemCount(),
            'subtotal' => (float) $order->getSubtotal(),
            'shipping_amount' => (float) $order->getShippingAmount(),
            'tax_amount' => (float) $order->getTaxAmount(),
            'discount_amount' => (float) abs($order->getDiscountAmount()),
        ];

        if ($order->getCouponCode()) {
            $properties['coupon'] = $order->getCouponCode();
        }

        return $properties;
    }

    private function getProductCategory($item): ?string
    {
        // Implementation depends on category structure
        // Could use product's category collection
        return null;
    }
}
```

### 2. Add to Cart Observer

**Event**: `checkout_cart_product_add_after`

```php
<?php
declare(strict_types=1);

namespace Mbuzz\Tracking\Observer;

use Magento\Framework\Event\Observer;
use Magento\Framework\Event\ObserverInterface;
use Mbuzz\Tracking\Model\Client;
use Mbuzz\Tracking\Model\Config;
use Mbuzz\Tracking\Model\EventBuilder;
use Psr\Log\LoggerInterface;

class AddToCartObserver implements ObserverInterface
{
    public function __construct(
        private Client $client,
        private Config $config,
        private EventBuilder $eventBuilder,
        private LoggerInterface $logger
    ) {}

    public function execute(Observer $observer): void
    {
        if (!$this->config->shouldTrackAddToCart()) {
            return;
        }

        try {
            /** @var \Magento\Quote\Model\Quote\Item $quoteItem */
            $quoteItem = $observer->getEvent()->getQuoteItem();
            $product = $quoteItem->getProduct();

            $event = $this->eventBuilder->buildAddToCart(
                $product->getSku(),
                $product->getName(),
                (float) $quoteItem->getPrice(),
                (int) $quoteItem->getQty(),
                [
                    'product_id' => $product->getId(),
                    'product_type' => $product->getTypeId(),
                ]
            );

            $this->client->track($event);

        } catch (\Exception $e) {
            $this->logger->error('[Mbuzz] Add to cart tracking failed: ' . $e->getMessage());
        }
    }
}
```

### 3. Customer Registration Observer

**Event**: `customer_register_success`

```php
<?php
declare(strict_types=1);

namespace Mbuzz\Tracking\Observer;

use Magento\Framework\Event\Observer;
use Magento\Framework\Event\ObserverInterface;
use Mbuzz\Tracking\Model\Client;
use Mbuzz\Tracking\Model\Config;
use Mbuzz\Tracking\Model\EventBuilder;
use Psr\Log\LoggerInterface;

class CustomerRegisterObserver implements ObserverInterface
{
    public function __construct(
        private Client $client,
        private Config $config,
        private EventBuilder $eventBuilder,
        private LoggerInterface $logger
    ) {}

    public function execute(Observer $observer): void
    {
        if (!$this->config->shouldTrackRegistration()) {
            return;
        }

        try {
            /** @var \Magento\Customer\Model\Customer $customer */
            $customer = $observer->getEvent()->getCustomer();

            $event = $this->eventBuilder->buildSignup(
                (string) $customer->getId(),
                [
                    'email' => $customer->getEmail(),
                    'first_name' => $customer->getFirstname(),
                    'last_name' => $customer->getLastname(),
                    'created_at' => $customer->getCreatedAt(),
                ]
            );

            $this->client->track($event);

        } catch (\Exception $e) {
            $this->logger->error('[Mbuzz] Registration tracking failed: ' . $e->getMessage());
        }
    }
}
```

### 4. Customer Login Observer (Identify)

**Event**: `customer_login`

```php
<?php
declare(strict_types=1);

namespace Mbuzz\Tracking\Observer;

use Magento\Framework\Event\Observer;
use Magento\Framework\Event\ObserverInterface;
use Mbuzz\Tracking\Model\Client;
use Mbuzz\Tracking\Model\Config;
use Mbuzz\Tracking\Model\EventBuilder;
use Psr\Log\LoggerInterface;

class CustomerLoginObserver implements ObserverInterface
{
    public function __construct(
        private Client $client,
        private Config $config,
        private EventBuilder $eventBuilder,
        private LoggerInterface $logger
    ) {}

    public function execute(Observer $observer): void
    {
        if (!$this->config->isEnabled()) {
            return;
        }

        try {
            /** @var \Magento\Customer\Model\Customer $customer */
            $customer = $observer->getEvent()->getCustomer();

            // Track as identify event to link visitor to user
            $event = $this->eventBuilder->build('identify', [
                'email' => $customer->getEmail(),
                'first_name' => $customer->getFirstname(),
                'last_name' => $customer->getLastname(),
            ]);

            $event['user_id'] = (string) $customer->getId();

            $this->client->track($event);

        } catch (\Exception $e) {
            $this->logger->error('[Mbuzz] Login tracking failed: ' . $e->getMessage());
        }
    }
}
```

---

## Events Configuration

```xml
<!-- etc/events.xml (global) -->
<?xml version="1.0"?>
<config xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xsi:noNamespaceSchemaLocation="urn:magento:framework:Event/etc/events.xsd">

    <!-- Purchase tracking (server-side, after payment confirmed) -->
    <event name="sales_order_payment_pay">
        <observer name="mbuzz_order_place"
                  instance="Mbuzz\Tracking\Observer\OrderPlaceObserver"/>
    </event>

    <!-- Refund tracking -->
    <event name="sales_order_creditmemo_save_after">
        <observer name="mbuzz_order_refund"
                  instance="Mbuzz\Tracking\Observer\OrderRefundObserver"/>
    </event>

</config>
```

```xml
<!-- etc/frontend/events.xml -->
<?xml version="1.0"?>
<config xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xsi:noNamespaceSchemaLocation="urn:magento:framework:Event/etc/events.xsd">

    <!-- Add to cart -->
    <event name="checkout_cart_product_add_after">
        <observer name="mbuzz_add_to_cart"
                  instance="Mbuzz\Tracking\Observer\AddToCartObserver"/>
    </event>

    <!-- Remove from cart -->
    <event name="sales_quote_remove_item">
        <observer name="mbuzz_remove_from_cart"
                  instance="Mbuzz\Tracking\Observer\RemoveFromCartObserver"/>
    </event>

    <!-- Customer registration -->
    <event name="customer_register_success">
        <observer name="mbuzz_customer_register"
                  instance="Mbuzz\Tracking\Observer\CustomerRegisterObserver"/>
    </event>

    <!-- Customer login (identify) -->
    <event name="customer_login">
        <observer name="mbuzz_customer_login"
                  instance="Mbuzz\Tracking\Observer\CustomerLoginObserver"/>
    </event>

    <!-- Page views -->
    <event name="controller_action_postdispatch">
        <observer name="mbuzz_page_view"
                  instance="Mbuzz\Tracking\Observer\PageViewObserver"/>
    </event>

</config>
```

---

## Event Mapping

### Magento Events → Mbuzz Events

| Magento Event | Mbuzz Event Type | Properties |
|---------------|------------------|------------|
| `controller_action_postdispatch` | `page_view` | url, referrer, path |
| `catalog_controller_product_view` | `product_view` | product_sku, product_name, price, category |
| `checkout_cart_product_add_after` | `add_to_cart` | product_sku, product_name, price, quantity |
| `sales_quote_remove_item` | `remove_from_cart` | product_sku, quantity |
| `checkout_index_index` | `checkout_started` | cart_value, item_count |
| `sales_order_payment_pay` | `purchase` | order_id, revenue, currency, items[] |
| `sales_order_creditmemo_save_after` | `refund` | order_id, refund_amount |
| `customer_register_success` | `signup` | email, first_name, last_name |
| `customer_login` | `identify` | email, user_id |

### E-commerce Funnel Tracking

```
page_view (landing)
    ↓
product_view
    ↓
add_to_cart
    ↓
checkout_started
    ↓
purchase [CONVERSION]
```

Each event automatically includes:
- `visitor_id` (from cookie)
- `session_id` (from cookie)
- `user_id` (if logged in)
- `timestamp` (ISO8601 UTC)
- UTM parameters (if present in URL)

---

## Installation

### Via Composer (Recommended)

```bash
composer require mbuzz/module-tracking
bin/magento module:enable Mbuzz_Tracking
bin/magento setup:upgrade
bin/magento cache:flush
```

### Manual Installation

```bash
# Create directory
mkdir -p app/code/Mbuzz/Tracking

# Copy module files
# (download from GitHub or package)

# Enable module
bin/magento module:enable Mbuzz_Tracking
bin/magento setup:upgrade
bin/magento cache:flush
```

### Configuration

1. Go to **Stores > Configuration > Sales > Mbuzz Tracking**
2. Set **Enable Tracking** to **Yes**
3. Enter your **API Key** (get from [mbuzz.co/dashboard](https://mbuzz.co/dashboard))
4. Click **Test Connection** to verify
5. Configure which events to track
6. Save and flush cache

---

## CLI Commands

### Test API Connection

```bash
bin/magento mbuzz:test

# Output:
# Mbuzz API Connection Test
# =========================
# API URL: https://mbuzz.co/api/v1
# API Key: sk_test_****...****
#
# Testing connection...
# ✓ Connection successful
# Account: Acme Inc (acct_abc123)
```

### Send Test Event

```bash
bin/magento mbuzz:track --event="test_event" --properties='{"test":true}'

# Output:
# Sending test event...
# ✓ Event tracked successfully
```

---

## Troubleshooting

### Events Not Tracking

1. **Check module is enabled**: `bin/magento module:status Mbuzz_Tracking`
2. **Check configuration**: Stores > Configuration > Sales > Mbuzz Tracking
3. **Enable debug mode**: Set Debug Mode to Yes
4. **Check logs**: `tail -f var/log/mbuzz.log`

### Purchase Events Missing

The `sales_order_payment_pay` event only fires for fully paid orders. For payment methods that don't trigger this event:

1. Add fallback observer on `checkout_submit_all_after`
2. Or use `sales_order_place_after` with payment status check

### API Connection Fails

1. **Check API key**: Ensure key starts with `sk_test_` or `sk_live_`
2. **Check firewall**: Ensure server can reach `mbuzz.co`
3. **Check SSL**: Ensure PHP has valid CA certificates

```bash
# Test connectivity
curl -X GET https://mbuzz.co/api/v1/health

# Test with API key
curl -X GET https://mbuzz.co/api/v1/validate \
  -H "Authorization: Bearer sk_test_your_key_here"
```

---

## Performance Considerations

### High-Traffic Stores

For stores with >1000 orders/day, enable async processing:

1. Set **Use Message Queue** to **Yes**
2. Ensure RabbitMQ or database queue is configured
3. Events are queued and processed in background

### Caching

- Configuration is cached (flush after changes)
- Visitor/session IDs are cached in request scope
- No database queries for tracking (stateless)

### Timeouts

- API timeout: 5 seconds (non-blocking)
- Failed requests silently log error and continue
- No retry on failure (fire-and-forget)

---

## Security

### API Key Storage

- API key is encrypted using Magento's `Encrypted` backend model
- Never logged in debug mode (masked)
- Transmitted over HTTPS only

### Cookie Security

- `HttpOnly`: Yes (not accessible via JavaScript)
- `Secure`: Yes (HTTPS only)
- `SameSite`: Lax (prevents CSRF)

### Data Privacy

- IP addresses not sent to Mbuzz (anonymized server-side by Mbuzz)
- Customer emails only sent with explicit tracking enabled
- Compliant with GDPR (server-side tracking, no client profiling)

---

## Compatibility

### Magento Versions

| Magento Version | Supported |
|-----------------|-----------|
| 2.4.7+ | ✅ Yes |
| 2.4.6 | ✅ Yes |
| 2.4.5 | ✅ Yes |
| 2.4.4 | ✅ Yes |
| 2.4.0-2.4.3 | ⚠️ Untested |
| 2.3.x | ❌ No |

### PHP Versions

| PHP Version | Supported |
|-------------|-----------|
| 8.3 | ✅ Yes |
| 8.2 | ✅ Yes |
| 8.1 | ✅ Yes |
| 8.0 | ⚠️ Limited |
| 7.x | ❌ No |

### Adobe Commerce

Fully compatible with Adobe Commerce (Cloud and On-Premise).

---

## Testing

### Unit Tests

```bash
# Run all Mbuzz tests
bin/magento dev:tests:run unit -- --filter=Mbuzz

# Run specific test
vendor/bin/phpunit -c dev/tests/unit/phpunit.xml.dist \
  app/code/Mbuzz/Tracking/Test/Unit/
```

### Integration Tests

```bash
bin/magento dev:tests:run integration -- --filter=Mbuzz
```

### Manual Testing Checklist

- [ ] Install module via composer
- [ ] Configure API key in admin
- [ ] Test connection button works
- [ ] Visit product page → check for product_view event
- [ ] Add product to cart → check for add_to_cart event
- [ ] Complete checkout → check for purchase event
- [ ] Register new customer → check for signup event
- [ ] Login as customer → check for identify event
- [ ] Verify events appear in Mbuzz dashboard

---

## Changelog

### v0.1.0 (Initial Release)

- Basic event tracking (page views, add to cart, purchase)
- Customer registration and login tracking
- Admin configuration UI
- API key encryption
- Debug logging
- CLI test command

---

## References

### Magento Development

- [Magento 2 Development Best Practices](https://www.icecubedigital.com/blog/complete-guide-on-magento-2-development-best-practices/)
- [Adobe Commerce Events List](https://developer.adobe.com/commerce/php/development/components/events-and-observers/event-list/)
- [Magento 2 Events & Observers](https://www.mageplaza.com/devdocs/magento-2-create-events.html)
- [Module File Structure](https://developer.adobe.com/commerce/php/development/prepare/component-file-structure/)

### Server-Side Tracking

- [elgentos/magento2-serversideanalytics](https://github.com/elgentos/magento2-serversideanalytics)
- [Stape GTM Server Side for Magento](https://stape.io/solutions/gtm-server-side-extension-for-magento-2)
- [Server-Side GA4 for Magento](https://stape.io/blog/server-side-google-analytics-4-for-magento)

### Mbuzz Documentation

- [API Contract](../docs/sdk/api_contract.md)
- [SDK Registry](../docs/sdk/sdk_registry.md)
- [Event Properties](../docs/architecture/event_properties.md)
- [Attribution Methodology](../docs/architecture/attribution_methodology.md)

---

## Support

- **Documentation**: [mbuzz.co/docs](https://mbuzz.co/docs)
- **GitHub Issues**: [github.com/mbuzz-tracking/mbuzz-magento](https://github.com/mbuzz-tracking/mbuzz-magento)
- **Email**: support@mbuzz.co
