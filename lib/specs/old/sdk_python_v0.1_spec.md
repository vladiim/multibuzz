# Python SDK Specification

## Overview

Python SDK for mbuzz multi-touch attribution. Follows the same 4-call pattern as Ruby and Node SDKs.

**Package name**: `mbuzz`
**PyPI**: `pip install mbuzz`
**Repo**: `/Users/vlad/code/mbuzz-python`

---

## Public API

```python
import mbuzz

# Initialize (once on app start)
mbuzz.init(api_key="sk_live_...")

# Track journey events
mbuzz.event("page_view", url="/pricing", referrer="https://google.com")
mbuzz.event("button_click", button="signup", page="/home")

# Track conversions
mbuzz.conversion("purchase", revenue=99.99, currency="USD")
mbuzz.conversion("signup", is_acquisition=True)

# Link visitor to user identity
mbuzz.identify("user_123", traits={"email": "user@example.com", "plan": "pro"})

# Context accessors
mbuzz.visitor_id()  # Current visitor ID
mbuzz.session_id()  # Current session ID
mbuzz.user_id()     # Current user ID (if identified)
```

---

## Directory Structure

```
mbuzz-python/
├── pyproject.toml          # Package config (PEP 517)
├── README.md
├── LICENSE
├── src/
│   └── mbuzz/
│       ├── __init__.py     # Public API exports
│       ├── config.py       # Configuration singleton
│       ├── context.py      # ContextVar-based request context
│       ├── api.py          # HTTP client (requests or urllib)
│       ├── client/
│       │   ├── __init__.py
│       │   ├── track.py    # Event tracking
│       │   ├── identify.py # User identification
│       │   ├── conversion.py # Conversion tracking
│       │   └── session.py  # Session creation
│       ├── middleware/
│       │   ├── __init__.py
│       │   ├── django.py   # Django middleware
│       │   ├── flask.py    # Flask middleware (before_request/after_request)
│       │   └── fastapi.py  # FastAPI/Starlette middleware
│       └── utils/
│           ├── __init__.py
│           └── identifier.py # ID generation
└── tests/
    ├── __init__.py
    ├── test_config.py
    ├── test_api.py
    ├── test_client/
    └── test_middleware/
```

---

## Configuration

```python
# mbuzz/config.py

from dataclasses import dataclass, field
from typing import Optional, List

DEFAULT_API_URL = "https://mbuzz.co/api/v1"
DEFAULT_TIMEOUT = 5.0  # seconds

DEFAULT_SKIP_PATHS = [
    "/health", "/healthz", "/ping", "/up",
    "/static", "/assets", "/media",
    "/admin/jsi18n",  # Django admin
    "/__debug__",     # Django debug toolbar
]

DEFAULT_SKIP_EXTENSIONS = [
    ".js", ".css", ".map",
    ".png", ".jpg", ".jpeg", ".gif", ".ico", ".svg", ".webp",
    ".woff", ".woff2", ".ttf", ".eot",
]

@dataclass
class Config:
    api_key: str = ""
    api_url: str = DEFAULT_API_URL
    enabled: bool = True
    debug: bool = False
    timeout: float = DEFAULT_TIMEOUT
    skip_paths: List[str] = field(default_factory=list)
    skip_extensions: List[str] = field(default_factory=list)
    _initialized: bool = False

    def init(self, **kwargs):
        if not kwargs.get("api_key"):
            raise ValueError("api_key is required")

        self.api_key = kwargs["api_key"]
        self.api_url = kwargs.get("api_url", DEFAULT_API_URL)
        self.enabled = kwargs.get("enabled", True)
        self.debug = kwargs.get("debug", False)
        self.timeout = kwargs.get("timeout", DEFAULT_TIMEOUT)
        self.skip_paths = DEFAULT_SKIP_PATHS + kwargs.get("skip_paths", [])
        self.skip_extensions = DEFAULT_SKIP_EXTENSIONS + kwargs.get("skip_extensions", [])
        self._initialized = True

    def should_skip_path(self, path: str) -> bool:
        if any(path.startswith(skip) for skip in self.skip_paths):
            return True
        if any(path.endswith(ext) for ext in self.skip_extensions):
            return True
        return False

# Singleton
config = Config()
```

---

## Request Context (ContextVar)

Python 3.7+ has `contextvars` for async-safe context propagation:

```python
# mbuzz/context.py

from contextvars import ContextVar
from dataclasses import dataclass
from typing import Optional, Dict, Any

@dataclass
class RequestContext:
    visitor_id: str
    session_id: str
    user_id: Optional[str] = None
    url: Optional[str] = None
    referrer: Optional[str] = None

    def enrich_properties(self, properties: Dict[str, Any]) -> Dict[str, Any]:
        """Add url and referrer to properties if not already present."""
        result = {}
        if self.url:
            result["url"] = self.url
        if self.referrer:
            result["referrer"] = self.referrer
        result.update(properties)
        return result

# Context variable for current request
_context: ContextVar[Optional[RequestContext]] = ContextVar("mbuzz_context", default=None)

def get_context() -> Optional[RequestContext]:
    return _context.get()

def set_context(ctx: RequestContext) -> None:
    _context.set(ctx)

def clear_context() -> None:
    _context.set(None)
```

---

## HTTP Client

```python
# mbuzz/api.py

import json
import logging
from typing import Optional, Dict, Any
from urllib.request import Request, urlopen
from urllib.error import URLError, HTTPError

from .config import config

logger = logging.getLogger("mbuzz")

def post(path: str, payload: Dict[str, Any]) -> bool:
    """POST to API, return True on success, False on any failure."""
    if not config._initialized or not config.enabled:
        return False

    try:
        response = _make_request(path, payload)
        return 200 <= response.status < 300
    except Exception as e:
        if config.debug:
            logger.error(f"mbuzz API error: {e}")
        return False

def post_with_response(path: str, payload: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """POST to API, return parsed JSON on success, None on failure."""
    if not config._initialized or not config.enabled:
        return None

    try:
        response = _make_request(path, payload)
        if 200 <= response.status < 300:
            return json.loads(response.read().decode("utf-8"))
        return None
    except Exception as e:
        if config.debug:
            logger.error(f"mbuzz API error: {e}")
        return None

def _make_request(path: str, payload: Dict[str, Any]):
    """Make HTTP request to API."""
    base_url = config.api_url.rstrip("/")
    clean_path = path.lstrip("/")
    url = f"{base_url}/{clean_path}"

    data = json.dumps(payload).encode("utf-8")

    req = Request(url, data=data, method="POST")
    req.add_header("Authorization", f"Bearer {config.api_key}")
    req.add_header("Content-Type", "application/json")
    req.add_header("User-Agent", "mbuzz-python/0.1.0")

    if config.debug:
        logger.debug(f"mbuzz POST {url}: {payload}")

    return urlopen(req, timeout=config.timeout)
```

---

## Cookie Constants

```python
# mbuzz/cookies.py

VISITOR_COOKIE = "_mbuzz_vid"
SESSION_COOKIE = "_mbuzz_sid"

VISITOR_MAX_AGE = 63072000  # 2 years in seconds
SESSION_MAX_AGE = 1800      # 30 minutes in seconds
```

---

## ID Generation

```python
# mbuzz/utils/identifier.py

import secrets

def generate_id() -> str:
    """Generate 64-character hex string (256 bits of entropy)."""
    return secrets.token_hex(32)
```

---

## Django Middleware

```python
# mbuzz/middleware/django.py

import threading
from typing import Callable
from django.http import HttpRequest, HttpResponse

from ..config import config
from ..context import RequestContext, set_context, clear_context
from ..cookies import VISITOR_COOKIE, SESSION_COOKIE, VISITOR_MAX_AGE, SESSION_MAX_AGE
from ..utils.identifier import generate_id
from ..client.session import create_session

class MbuzzMiddleware:
    def __init__(self, get_response: Callable[[HttpRequest], HttpResponse]):
        self.get_response = get_response

    def __call__(self, request: HttpRequest) -> HttpResponse:
        if not config._initialized or not config.enabled:
            return self.get_response(request)

        if config.should_skip_path(request.path):
            return self.get_response(request)

        # Get or create visitor ID
        visitor_id = request.COOKIES.get(VISITOR_COOKIE) or generate_id()
        is_new_visitor = VISITOR_COOKIE not in request.COOKIES

        # Get or create session ID
        session_id = request.COOKIES.get(SESSION_COOKIE) or generate_id()
        is_new_session = SESSION_COOKIE not in request.COOKIES

        # Get user ID from Django session
        user_id = request.session.get("user_id") if hasattr(request, "session") else None

        # Set context
        ctx = RequestContext(
            visitor_id=visitor_id,
            session_id=session_id,
            user_id=user_id,
            url=request.build_absolute_uri(),
            referrer=request.META.get("HTTP_REFERER"),
        )
        set_context(ctx)

        # Create session async if new
        if is_new_session:
            threading.Thread(
                target=create_session,
                args=(visitor_id, session_id, ctx.url, ctx.referrer),
                daemon=True
            ).start()

        try:
            response = self.get_response(request)
        finally:
            clear_context()

        # Set cookies
        secure = request.is_secure()
        response.set_cookie(
            VISITOR_COOKIE, visitor_id,
            max_age=VISITOR_MAX_AGE,
            httponly=True,
            samesite="Lax",
            secure=secure,
        )
        response.set_cookie(
            SESSION_COOKIE, session_id,
            max_age=SESSION_MAX_AGE,
            httponly=True,
            samesite="Lax",
            secure=secure,
        )

        return response
```

---

## Flask Integration

```python
# mbuzz/middleware/flask.py

import threading
from flask import Flask, request, g, Response
from typing import Optional

from ..config import config
from ..context import RequestContext, set_context, clear_context
from ..cookies import VISITOR_COOKIE, SESSION_COOKIE, VISITOR_MAX_AGE, SESSION_MAX_AGE
from ..utils.identifier import generate_id
from ..client.session import create_session

def init_app(app: Flask) -> None:
    """Initialize mbuzz tracking for Flask app."""

    @app.before_request
    def before_request():
        if not config._initialized or not config.enabled:
            return

        if config.should_skip_path(request.path):
            return

        visitor_id = request.cookies.get(VISITOR_COOKIE) or generate_id()
        session_id = request.cookies.get(SESSION_COOKIE) or generate_id()
        is_new_session = VISITOR_COOKIE not in request.cookies

        ctx = RequestContext(
            visitor_id=visitor_id,
            session_id=session_id,
            user_id=None,
            url=request.url,
            referrer=request.referrer,
        )
        set_context(ctx)
        g.mbuzz_visitor_id = visitor_id
        g.mbuzz_session_id = session_id
        g.mbuzz_is_new_visitor = VISITOR_COOKIE not in request.cookies
        g.mbuzz_is_new_session = is_new_session

        if is_new_session:
            threading.Thread(
                target=create_session,
                args=(visitor_id, session_id, ctx.url, ctx.referrer),
                daemon=True
            ).start()

    @app.after_request
    def after_request(response: Response) -> Response:
        if not hasattr(g, "mbuzz_visitor_id"):
            return response

        secure = request.is_secure
        response.set_cookie(
            VISITOR_COOKIE, g.mbuzz_visitor_id,
            max_age=VISITOR_MAX_AGE,
            httponly=True,
            samesite="Lax",
            secure=secure,
        )
        response.set_cookie(
            SESSION_COOKIE, g.mbuzz_session_id,
            max_age=SESSION_MAX_AGE,
            httponly=True,
            samesite="Lax",
            secure=secure,
        )
        return response

    @app.teardown_request
    def teardown_request(exception=None):
        clear_context()
```

---

## FastAPI/Starlette Middleware

```python
# mbuzz/middleware/fastapi.py

import threading
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

from ..config import config
from ..context import RequestContext, set_context, clear_context
from ..cookies import VISITOR_COOKIE, SESSION_COOKIE, VISITOR_MAX_AGE, SESSION_MAX_AGE
from ..utils.identifier import generate_id
from ..client.session import create_session

class MbuzzMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next) -> Response:
        if not config._initialized or not config.enabled:
            return await call_next(request)

        if config.should_skip_path(request.url.path):
            return await call_next(request)

        visitor_id = request.cookies.get(VISITOR_COOKIE) or generate_id()
        session_id = request.cookies.get(SESSION_COOKIE) or generate_id()
        is_new_session = SESSION_COOKIE not in request.cookies

        ctx = RequestContext(
            visitor_id=visitor_id,
            session_id=session_id,
            user_id=None,
            url=str(request.url),
            referrer=request.headers.get("referer"),
        )
        set_context(ctx)

        if is_new_session:
            threading.Thread(
                target=create_session,
                args=(visitor_id, session_id, ctx.url, ctx.referrer),
                daemon=True
            ).start()

        try:
            response = await call_next(request)
        finally:
            clear_context()

        # Set cookies
        secure = request.url.scheme == "https"
        response.set_cookie(
            VISITOR_COOKIE, visitor_id,
            max_age=VISITOR_MAX_AGE,
            httponly=True,
            samesite="lax",
            secure=secure,
        )
        response.set_cookie(
            SESSION_COOKIE, session_id,
            max_age=SESSION_MAX_AGE,
            httponly=True,
            samesite="lax",
            secure=secure,
        )

        return response
```

---

## Client Methods

### Track Request

```python
# mbuzz/client/track.py

from typing import Dict, Any, Optional
from dataclasses import dataclass

from ..api import post_with_response
from ..context import get_context

@dataclass
class TrackResult:
    success: bool
    event_id: Optional[str] = None
    event_type: Optional[str] = None
    visitor_id: Optional[str] = None
    session_id: Optional[str] = None

def track(
    event_type: str,
    visitor_id: Optional[str] = None,
    session_id: Optional[str] = None,
    user_id: Optional[str] = None,
    properties: Optional[Dict[str, Any]] = None,
) -> TrackResult:
    """Track an event."""
    ctx = get_context()

    # Use context values as fallback
    visitor_id = visitor_id or (ctx.visitor_id if ctx else None)
    session_id = session_id or (ctx.session_id if ctx else None)
    user_id = user_id or (ctx.user_id if ctx else None)

    # Must have at least visitor_id or user_id
    if not visitor_id and not user_id:
        return TrackResult(success=False)

    # Enrich properties with context
    props = properties or {}
    if ctx:
        props = ctx.enrich_properties(props)

    payload = {
        "events": [{
            "event_type": event_type,
            "visitor_id": visitor_id,
            "session_id": session_id,
            "user_id": user_id,
            "properties": props,
            "timestamp": _iso_now(),
        }]
    }

    response = post_with_response("/events", payload)
    if not response or not response.get("events"):
        return TrackResult(success=False)

    event = response["events"][0]
    return TrackResult(
        success=True,
        event_id=event.get("id"),
        event_type=event_type,
        visitor_id=visitor_id,
        session_id=session_id,
    )

def _iso_now() -> str:
    from datetime import datetime, timezone
    return datetime.now(timezone.utc).isoformat()
```

### Identify Request

```python
# mbuzz/client/identify.py

from typing import Dict, Any, Optional, Union

from ..api import post
from ..context import get_context

def identify(
    user_id: Union[str, int],
    visitor_id: Optional[str] = None,
    traits: Optional[Dict[str, Any]] = None,
) -> bool:
    """Identify a user and link to visitor."""
    ctx = get_context()
    visitor_id = visitor_id or (ctx.visitor_id if ctx else None)

    if not user_id:
        return False

    payload = {
        "user_id": str(user_id),
        "visitor_id": visitor_id,
        "traits": traits or {},
    }

    return post("/identify", payload)
```

### Conversion Request

```python
# mbuzz/client/conversion.py

from typing import Dict, Any, Optional, Union
from dataclasses import dataclass

from ..api import post_with_response
from ..context import get_context

@dataclass
class ConversionResult:
    success: bool
    conversion_id: Optional[str] = None
    attribution: Optional[Dict[str, Any]] = None

def conversion(
    conversion_type: str,
    visitor_id: Optional[str] = None,
    user_id: Optional[Union[str, int]] = None,
    event_id: Optional[str] = None,
    revenue: Optional[float] = None,
    currency: str = "USD",
    is_acquisition: bool = False,
    inherit_acquisition: bool = False,
    properties: Optional[Dict[str, Any]] = None,
) -> ConversionResult:
    """Track a conversion."""
    ctx = get_context()

    visitor_id = visitor_id or (ctx.visitor_id if ctx else None)
    user_id = user_id or (ctx.user_id if ctx else None)

    if not visitor_id and not user_id:
        return ConversionResult(success=False)

    payload = {
        "conversion_type": conversion_type,
        "visitor_id": visitor_id,
        "user_id": str(user_id) if user_id else None,
        "event_id": event_id,
        "revenue": revenue,
        "currency": currency,
        "is_acquisition": is_acquisition,
        "inherit_acquisition": inherit_acquisition,
        "properties": properties or {},
    }

    response = post_with_response("/conversions", payload)
    if not response:
        return ConversionResult(success=False)

    return ConversionResult(
        success=True,
        conversion_id=response.get("conversion", {}).get("id"),
        attribution=response.get("attribution"),
    )
```

### Session Request

```python
# mbuzz/client/session.py

from typing import Optional
from datetime import datetime, timezone

from ..api import post

def create_session(
    visitor_id: str,
    session_id: str,
    url: str,
    referrer: Optional[str] = None,
) -> bool:
    """Create a new session (called async from middleware)."""
    payload = {
        "session": {
            "visitor_id": visitor_id,
            "session_id": session_id,
            "url": url,
            "referrer": referrer,
            "started_at": datetime.now(timezone.utc).isoformat(),
        }
    }

    return post("/sessions", payload)
```

---

## Main Module (__init__.py)

```python
# mbuzz/__init__.py

from typing import Dict, Any, Optional, Union

from .config import config
from .context import get_context
from .client.track import track, TrackResult
from .client.identify import identify
from .client.conversion import conversion, ConversionResult

__version__ = "0.1.0"

def init(
    api_key: str,
    api_url: str = None,
    enabled: bool = True,
    debug: bool = False,
    timeout: float = None,
    skip_paths: list = None,
    skip_extensions: list = None,
) -> None:
    """Initialize the mbuzz SDK."""
    config.init(
        api_key=api_key,
        api_url=api_url,
        enabled=enabled,
        debug=debug,
        timeout=timeout,
        skip_paths=skip_paths or [],
        skip_extensions=skip_extensions or [],
    )

def event(event_type: str, **properties) -> TrackResult:
    """Track an event."""
    return track(event_type=event_type, properties=properties)

def visitor_id() -> Optional[str]:
    """Get current visitor ID."""
    ctx = get_context()
    return ctx.visitor_id if ctx else None

def session_id() -> Optional[str]:
    """Get current session ID."""
    ctx = get_context()
    return ctx.session_id if ctx else None

def user_id() -> Optional[str]:
    """Get current user ID."""
    ctx = get_context()
    return ctx.user_id if ctx else None

# Re-export for explicit imports
__all__ = [
    "init",
    "event",
    "conversion",
    "identify",
    "visitor_id",
    "session_id",
    "user_id",
    "TrackResult",
    "ConversionResult",
    "__version__",
]
```

---

## Package Configuration (pyproject.toml)

```toml
[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[project]
name = "mbuzz"
version = "0.1.0"
description = "Multi-touch attribution SDK for Python"
readme = "README.md"
license = "MIT"
requires-python = ">=3.8"
authors = [
    { name = "Mbuzz", email = "support@mbuzz.co" }
]
classifiers = [
    "Development Status :: 4 - Beta",
    "Framework :: Django",
    "Framework :: Flask",
    "Framework :: FastAPI",
    "Intended Audience :: Developers",
    "License :: OSI Approved :: MIT License",
    "Programming Language :: Python :: 3",
    "Programming Language :: Python :: 3.8",
    "Programming Language :: Python :: 3.9",
    "Programming Language :: Python :: 3.10",
    "Programming Language :: Python :: 3.11",
    "Programming Language :: Python :: 3.12",
]
keywords = ["analytics", "attribution", "marketing", "tracking"]

[project.urls]
Homepage = "https://mbuzz.co"
Documentation = "https://mbuzz.co/docs/python"
Repository = "https://github.com/mbuzz/mbuzz-python"

[project.optional-dependencies]
django = []  # No extra deps needed
flask = []   # No extra deps needed
fastapi = ["starlette"]
dev = ["pytest", "pytest-cov", "black", "ruff", "mypy"]

[tool.hatch.build.targets.wheel]
packages = ["src/mbuzz"]

[tool.ruff]
line-length = 100
select = ["E", "F", "I", "N", "W"]

[tool.mypy]
python_version = "3.8"
strict = true
```

---

## Integration Testing

Add Python test app to SDK integration tests:

**Port**: 4003 (as per plan)

```
sdk_integration_tests/apps/mbuzz_python_testapp/
├── requirements.txt
├── app.py              # Flask app
└── templates/
    └── index.html
```

Update test scenarios to run against Python SDK with `SDK=python`.

---

## Implementation Checklist

- [ ] Create `/Users/vlad/code/mbuzz-python` repo
- [ ] Set up pyproject.toml
- [ ] Implement config.py
- [ ] Implement context.py
- [ ] Implement api.py
- [ ] Implement utils/identifier.py
- [ ] Implement client/track.py
- [ ] Implement client/identify.py
- [ ] Implement client/conversion.py
- [ ] Implement client/session.py
- [ ] Implement __init__.py (main module)
- [ ] Implement middleware/django.py
- [ ] Implement middleware/flask.py
- [ ] Implement middleware/fastapi.py
- [ ] Add unit tests
- [ ] Create Flask test app for integration tests
- [ ] Run integration tests
- [ ] Update docs
