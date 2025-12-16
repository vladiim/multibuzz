<?php

declare(strict_types=1);

namespace App;

use Mbuzz\Adapter\SymfonySubscriber;
use Mbuzz\Mbuzz;
use Symfony\Component\EventDispatcher\EventDispatcher;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\RequestStack;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\HttpKernel\Controller\ArgumentResolver;
use Symfony\Component\HttpKernel\Controller\ControllerResolver;
use Symfony\Component\HttpKernel\EventListener\RouterListener;
use Symfony\Component\HttpKernel\HttpKernel;
use Symfony\Component\Routing\Matcher\UrlMatcher;
use Symfony\Component\Routing\RequestContext;
use Symfony\Component\Routing\Route;
use Symfony\Component\Routing\RouteCollection;

final class Kernel
{
    private HttpKernel $httpKernel;
    private EventDispatcher $dispatcher;

    public function __construct()
    {
        $this->initializeMbuzz();
        $this->dispatcher = new EventDispatcher();
        $this->httpKernel = $this->createHttpKernel();
    }

    public function handle(Request $request): Response
    {
        return $this->httpKernel->handle($request);
    }

    private function initializeMbuzz(): void
    {
        // Load test env file if it exists
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

        Mbuzz::init([
            'api_key' => $apiKey,
            'api_url' => $apiUrl,
            'debug' => (getenv('MBUZZ_DEBUG') ?: 'false') === 'true',
        ]);
    }

    private function createHttpKernel(): HttpKernel
    {
        $routes = $this->createRoutes();
        $context = new RequestContext();
        $matcher = new UrlMatcher($routes, $context);
        $requestStack = new RequestStack();

        // Add router listener
        $this->dispatcher->addSubscriber(new RouterListener($matcher, $requestStack));

        // Add Mbuzz tracking subscriber
        $this->dispatcher->addSubscriber(new SymfonySubscriber());

        $controllerResolver = new ControllerResolver();
        $argumentResolver = new ArgumentResolver();

        return new HttpKernel($this->dispatcher, $controllerResolver, $requestStack, $argumentResolver);
    }

    private function createRoutes(): RouteCollection
    {
        $routes = new RouteCollection();

        $routes->add('home', new Route('/', [
            '_controller' => [Controller::class, 'index'],
        ]));

        $routes->add('api_ids', new Route('/api/ids', [
            '_controller' => [Controller::class, 'ids'],
        ], methods: ['GET']));

        $routes->add('api_event', new Route('/api/event', [
            '_controller' => [Controller::class, 'event'],
        ], methods: ['POST']));

        $routes->add('api_identify', new Route('/api/identify', [
            '_controller' => [Controller::class, 'identify'],
        ], methods: ['POST']));

        $routes->add('api_conversion', new Route('/api/conversion', [
            '_controller' => [Controller::class, 'conversion'],
        ], methods: ['POST']));

        return $routes;
    }
}
