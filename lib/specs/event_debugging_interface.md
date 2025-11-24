# Event Debugging Interface Specification

## Overview

A real-time debugging interface that allows developers to tag events with a unique debug parameter (e.g., `?debug=howdy-123`) and monitor their ingestion, enrichment, and processing in real-time. This enables developers to validate their implementation, troubleshoot issues, and understand how Multibuzz processes their events.

---

## Problem Statement

Developers implementing Multibuzz need to:
- Verify events are being captured correctly
- Understand what data is being extracted (UTM params, referrers, categories, etc.)
- Debug why certain events might not appear as expected
- Validate their implementation before going to production
- Troubleshoot issues in production without affecting real users

Current challenges:
- No way to filter events for testing purposes
- Hard to distinguish test events from production traffic
- No visibility into enrichment process (what got extracted/categorized)
- Developers must search through all events to find their test data
- No real-time feedback during implementation

---

## Solution: Debug Parameter Flow

### User Journey

1. **Developer adds debug parameter to URL**
   ```
   https://example.com/pricing?debug=howdy-123
   ```

2. **Multibuzz captures event with debug flag**
   - Event automatically tagged with `debug: "howdy-123"`
   - Event marked as debuggable in database
   - Debug parameter extracted during ingestion

3. **Developer opens Debug Console**
   - Navigates to `/debug` in Multibuzz dashboard
   - Enters debug ID: `howdy-123`
   - Sees live stream of events matching that debug ID

4. **Events stream in real-time**
   - New events appear instantly (WebSocket/SSE)
   - Shows enrichment data as processed
   - Color-coded by event type
   - Expandable to see full payload

5. **Developer clicks event to inspect**
   - Full event data with enrichment breakdown
   - Shows extracted UTM parameters
   - Shows categorization (domain, category, channel)
   - Shows session context
   - Shows visitor identification
   - Shows any validation errors or warnings

---

## Domain Language

### Core Concepts

- **Debug ID**: Unique identifier attached to URL via `?debug=xxx` parameter
- **Debug Session**: Collection of all events tagged with same debug ID
- **Event Stream**: Real-time feed of events for a debug session
- **Enrichment Data**: Data extracted/calculated during event processing (UTMs, referrer, category, etc.)
- **Debug Console**: Dashboard interface for monitoring debug sessions
- **Debug Event**: Event tagged with debug parameter (stored with `debug_id` field)
- **Event Inspector**: Detailed view of individual event with enrichment breakdown

### States

- **Pending**: Event received, queued for processing
- **Processing**: Event being enriched and validated
- **Processed**: Event successfully stored with enrichments
- **Failed**: Event failed validation or processing
- **Rejected**: Event rejected during ingestion (invalid format, rate limited, etc.)

### Categorization

Events are categorized during enrichment:
- **Channel**: organic, paid, direct, referral, social, email
- **Domain**: Primary website domain (e.g., google.com, facebook.com)
- **Category**: search_engine, social_media, advertising, etc.
- **UTM Data**: source, medium, campaign, content, term

---

## Architecture & Design Patterns

### 1. Event Ingestion with Debug Flag

**Pattern**: Decorator Pattern for Debug Enrichment

```ruby
# Service wraps standard ingestion with debug extraction
Event::DebugIngestionService
  - Extracts debug parameter from event properties
  - Tags event with debug_id if present
  - Sets debug_enabled flag on event
  - Delegates to standard Event::IngestionService
```

### 2. Real-Time Streaming

**Pattern**: Observer Pattern + Pub/Sub

```ruby
# After event processing, broadcast to debug channel
Event::DebugBroadcaster
  - Subscribes to event processing completion
  - Broadcasts to ActionCable channel: DebugChannel
  - Only broadcasts events with debug_enabled: true
  - Scoped to account (multi-tenancy)
```

**Technology**: ActionCable (WebSocket) or Hotwire Turbo Streams

### 3. Debug Console Interface

**Pattern**: Single Page Component with Live Updates

```
/debug
  → DebugConsole::ShowController
    → renders debug console view
    → establishes WebSocket connection
    → subscribes to debug channel for account
```

### 4. Event Inspector

**Pattern**: Presenter Pattern for Rich Display

```ruby
Event::DebugPresenter
  - Wraps event with formatted display methods
  - Extracts enrichment data into sections
  - Color codes by status/type
  - Formats timestamps, URLs, etc.
```

### 5. Query Architecture

**Pattern**: Query Object for Debug Filtering

```ruby
Events::DebugQuery
  - Finds events by debug_id and account
  - Orders by occurred_at (most recent first)
  - Includes enrichment data
  - Paginates results
```

---

## Feature Breakdown

### F1: Debug Parameter Extraction

**Automatic extraction of debug parameter from URLs and events**

#### Acceptance Criteria
- [x] System extracts `?debug=xxx` from page_view URLs
- [x] System extracts `debug` property from custom events
- [x] Debug ID stored in `events.debug_id` column (string, indexed)
- [x] Debug flag stored in `events.debug_enabled` (boolean, indexed, default: false)
- [x] Debug parameter removed from display URLs (privacy)
- [x] Debug IDs are case-insensitive (stored lowercase)
- [x] Debug IDs validated (alphanumeric + hyphens/underscores only, max 64 chars)
- [x] Invalid debug IDs logged but don't fail event ingestion

#### Examples

**Page View Event**:
```javascript
// URL: https://example.com/pricing?debug=test-123&utm_source=google
{
  event_type: "page_view",
  properties: {
    url: "https://example.com/pricing?debug=test-123&utm_source=google",
    // ... other properties
  }
}

// Stored as:
{
  event_type: "page_view",
  debug_id: "test-123",
  debug_enabled: true,
  properties: {
    url: "https://example.com/pricing",  // debug param stripped
    original_url: "https://example.com/pricing?debug=test-123&utm_source=google",
    utm_source: "google"
  }
}
```

**Custom Event**:
```javascript
// JavaScript
multibuzz.track("signup_completed", {
  debug: "test-signup-flow",
  plan: "pro"
});

// Stored as:
{
  event_type: "signup_completed",
  debug_id: "test-signup-flow",
  debug_enabled: true,
  properties: {
    plan: "pro"
    // debug removed from properties
  }
}
```

---

### F2: Debug Console UI

**Dashboard interface for entering debug ID and viewing event stream**

#### Acceptance Criteria
- [x] Route: `/debug` accessible from main navigation
- [x] Input field for debug ID with validation
- [x] "Start Debugging" button to activate stream
- [x] Live event counter (e.g., "12 events captured")
- [x] Time range filter (last 1h, 24h, 7d, 30d, all time)
- [x] Event type filter (page_view, custom events, all)
- [x] Clear/reset button to start new debug session
- [x] Shareable debug URL: `/debug?id=test-123` (pre-fills debug ID)
- [x] Help text with example usage
- [x] Empty state with getting started instructions
- [x] Export debug events as JSON

#### UI Layout

```
┌─────────────────────────────────────────────────┐
│ Debug Console                                   │
├─────────────────────────────────────────────────┤
│                                                 │
│  Debug ID: [____________________] [Start Debug] │
│                                                 │
│  💡 Add ?debug=your-id to your URL to track    │
│     events in real-time                         │
│                                                 │
│  Example:                                       │
│  https://example.com?debug=test-123            │
│                                                 │
├─────────────────────────────────────────────────┤
│  Filters: [Last 24h ▾] [All Events ▾]         │
│  Status: 🟢 Listening for events...             │
│  Captured: 12 events                            │
│                                                 │
├─────────────────────────────────────────────────┤
│  Event Stream                                   │
│  ┌───────────────────────────────────────────┐ │
│  │ 🟦 page_view          2:34:12 PM          │ │
│  │    /pricing                                │ │
│  │    → utm_source: google, channel: paid     │ │
│  │    [Expand ▾]                              │ │
│  ├───────────────────────────────────────────┤ │
│  │ 🟩 signup_completed   2:34:45 PM          │ │
│  │    plan: pro                               │ │
│  │    → channel: paid (attributed)            │ │
│  │    [Expand ▾]                              │ │
│  └───────────────────────────────────────────┘ │
│                                                 │
│  [Export as JSON]  [Clear]                     │
└─────────────────────────────────────────────────┘
```

---

### F3: Real-Time Event Streaming

**Events appear in console as they're processed (WebSocket/SSE)**

#### Acceptance Criteria
- [x] WebSocket connection established on debug start
- [x] New events appear within 1 second of processing
- [x] Events auto-scroll (with option to pause)
- [x] Visual indicator when new event arrives (fade-in animation)
- [x] Connection status indicator (connected/disconnected)
- [x] Auto-reconnect on connection loss
- [x] Events scoped to current account (multi-tenancy)
- [x] Events scoped to specific debug_id
- [x] Maximum 1000 events displayed (pagination/load more)
- [x] Events ordered by occurred_at DESC (newest first)

#### Technical Implementation

**ActionCable Channel**:
```ruby
# app/channels/debug_channel.rb
class DebugChannel < ApplicationCable::Channel
  def subscribed
    stream_for current_account, "debug_#{params[:debug_id]}"
  end

  def unsubscribed
    stop_all_streams
  end
end
```

**Broadcasting**:
```ruby
# app/services/event/debug_broadcaster.rb
module Event
  class DebugBroadcaster
    def initialize(event)
      @event = event
    end

    def call
      return unless event.debug_enabled?

      DebugChannel.broadcast_to(
        event.account,
        "debug_#{event.debug_id}",
        event_payload
      )
    end

    private

    def event_payload
      Event::DebugPresenter.new(event).as_json
    end
  end
end
```

---

### F4: Event Card (Collapsed View)

**Compact view of event in stream**

#### Acceptance Criteria
- [x] Event type icon and name
- [x] Timestamp (relative: "2 minutes ago" + absolute on hover)
- [x] Primary property (URL for page_view, event name for custom)
- [x] Key enrichment summary (1 line: utm_source, channel, category)
- [x] Status indicator (pending/processing/processed/failed)
- [x] Color coding by event type (page_view: blue, custom: green, error: red)
- [x] Expand/collapse toggle
- [x] Quick copy debug ID button

#### Visual Design

```
┌─────────────────────────────────────────────────┐
│ 🟦 page_view                    2:34:12 PM ⏱   │
│    /pricing?utm_source=google                   │
│    → utm_source: google | channel: paid | 🔍   │
│    [Expand ▾]                          [Copy ID]│
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│ 🟩 signup_completed             2:34:45 PM ⏱   │
│    plan: pro                                    │
│    → channel: paid (attributed) | 🔍           │
│    [Expand ▾]                          [Copy ID]│
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│ 🟥 page_view                    2:35:01 PM ⏱   │
│    /checkout                                    │
│    ⚠️  Failed: missing visitor_id              │
│    [Expand ▾]                          [Copy ID]│
└─────────────────────────────────────────────────┘
```

---

### F5: Event Inspector (Expanded View)

**Detailed breakdown of event with all enrichment data**

#### Acceptance Criteria
- [x] Full event JSON (formatted, syntax highlighted)
- [x] Enrichment breakdown in organized sections
- [x] UTM parameters section (if present)
- [x] Referrer analysis section (domain, category, channel)
- [x] Session context (session_id, session start, page sequence)
- [x] Visitor context (visitor_id, first_seen, returning)
- [x] Attribution data (first touch, last touch)
- [x] Validation warnings/errors (if any)
- [x] Processing metadata (received_at, processed_at, latency)
- [x] Copy to clipboard buttons for JSON and event ID
- [x] Collapsible sections

#### Sections

**1. Event Overview**
- Event Type
- Event ID (prefix_id format: `evt_xxx`)
- Debug ID (with copy button)
- Status (pending/processing/processed/failed)
- Occurred At (ISO8601 + relative time)
- Processing Latency (time from occurred_at to processed_at)

**2. UTM Parameters** *(if present)*
- utm_source
- utm_medium
- utm_campaign
- utm_content
- utm_term
- Channel Classification (derived from UTMs)

**3. Referrer Analysis** *(if present)*
- Full Referrer URL
- Referrer Domain (extracted)
- Referrer Category (search_engine, social_media, etc.)
- Channel Classification (organic, referral, etc.)

**4. Page Context** *(page_view events only)*
- URL (clean, without debug param)
- Original URL (with debug param)
- Path
- Query Parameters (parsed)
- Page Title *(if captured)*

**5. Session Context**
- Session ID (prefix_id: `sess_xxx`)
- Session Started At
- Pages in Session (count)
- Session Duration (if ended)
- Landing Page
- Current Page Number in Session

**6. Visitor Context**
- Visitor ID (prefix_id: `vis_xxx`)
- First Seen At
- Returning Visitor? (boolean)
- Total Sessions (count)
- Total Events (count)

**7. Attribution** *(if available)*
- First Touch Channel
- First Touch Source
- Last Touch Channel
- Last Touch Source

**8. Custom Properties**
- All additional properties sent with event
- Formatted as key-value pairs

**9. Validation & Processing**
- Validation Status (valid/invalid)
- Validation Errors (if any)
- Validation Warnings (if any)
- Processing Errors (if any)

**10. Raw Event JSON**
- Full event payload
- Syntax highlighted
- Copy to clipboard button

---

### F6: Debug History & Persistence

**Save debug sessions for later review**

#### Acceptance Criteria
- [x] Debug events retained for 90 days
- [x] Debug sessions list (recent debug IDs used)
- [x] Reopen previous debug session by clicking saved debug ID
- [x] Auto-load last used debug ID on page load (optional)
- [x] Delete debug session (removes all events with that debug_id)
- [x] Privacy: Only account owner can see their debug events
- [x] Debug events excluded from analytics/reporting by default
- [x] Option to "promote" debug event to production (remove debug flag)

---

### F7: Debug Documentation & Help

**In-app guides and examples**

#### Acceptance Criteria
- [x] Getting started guide on empty state
- [x] JavaScript snippet for adding debug parameter
- [x] Example URLs with debug parameters
- [x] Common troubleshooting scenarios
- [x] Link to full documentation
- [x] Video tutorial (optional)
- [x] Interactive demo mode (fake events for testing UI)

#### Help Content

**Getting Started**:
```markdown
## How to Debug Your Events

1. **Add the debug parameter to your URL**
   ```
   https://yoursite.com/page?debug=my-test-123
   ```

2. **Visit the page** in your browser

3. **Enter the debug ID** (`my-test-123`) in the field above

4. **Watch events appear** in real-time as they're processed

## JavaScript SDK

You can also add debug parameters to custom events:

```javascript
multibuzz.track("button_clicked", {
  debug: "my-test-123",
  button: "Get Started"
});
```

## Common Issues

- **No events appearing?** Check that your API key is correctly installed
- **Missing UTM data?** Ensure UTM parameters are before the debug parameter
- **Events delayed?** Processing typically takes < 1 second, check connection status
```

---

### F8: Debug Filters & Search

**Filter and search within debug session**

#### Acceptance Criteria
- [x] Filter by event type (page_view, custom event names)
- [x] Filter by status (processed, failed, pending)
- [x] Filter by time range (last 1h, 24h, 7d, custom)
- [x] Search by URL/path (for page_view events)
- [x] Search by property values
- [x] Filter by channel (organic, paid, direct, etc.)
- [x] Filter by UTM source
- [x] Combine multiple filters (AND logic)
- [x] Reset all filters button

---

### F9: Debug Alerts & Notifications

**Notify developers of common issues**

#### Acceptance Criteria
- [x] Alert when event fails validation
- [x] Warning when UTM parameters malformed
- [x] Warning when visitor_id missing (if required)
- [x] Warning when session_id missing (if required)
- [x] Alert when event rejected (rate limited, invalid format)
- [x] Performance warning (slow enrichment, > 500ms)
- [x] Success notification when first event processed
- [x] Alerts shown inline in event card
- [x] Alert summary at top of console

#### Alert Types

```
✅ Success
  "Event processed successfully in 127ms"

⚠️  Warning
  "No visitor_id provided - event will not be attributed to visitor"
  "UTM parameters detected but utm_medium is missing"
  "Session_id not provided - new session created"

❌ Error
  "Event rejected: Invalid timestamp format"
  "Processing failed: Missing required field 'event_type'"
  "Rate limit exceeded: 10,000 events/hour"
```

---

### F10: Debug Export & Sharing

**Export debug data for external analysis**

#### Acceptance Criteria
- [x] Export all debug events as JSON
- [x] Export all debug events as CSV
- [x] Export single event as JSON
- [x] Copy event to clipboard (formatted)
- [x] Shareable debug link: `/debug?id=test-123`
- [x] Link pre-fills debug ID and starts stream
- [x] Link expires after 24 hours (security)
- [x] Option to generate permanent debug link (for demos)

---

## Data Model

### Database Schema

```ruby
# Migration: add_debug_columns_to_events
class AddDebugColumnsToEvents < ActiveRecord::Migration[7.1]
  def change
    add_column :events, :debug_id, :string
    add_column :events, :debug_enabled, :boolean, default: false, null: false

    add_index :events, [:account_id, :debug_id, :occurred_at],
      name: "index_events_on_account_debug_occurred"
    add_index :events, [:debug_enabled],
      where: "debug_enabled = true",
      name: "index_events_on_debug_enabled"
  end
end
```

### Model

```ruby
# app/models/event.rb
class Event < ApplicationRecord
  # ... existing code ...

  scope :debug_enabled, -> { where(debug_enabled: true) }
  scope :by_debug_id, ->(debug_id) {
    where(debug_id: debug_id.to_s.downcase)
  }

  before_validation :normalize_debug_id

  validates :debug_id,
    format: {
      with: /\A[a-z0-9_-]+\z/,
      message: "must contain only lowercase letters, numbers, hyphens, and underscores"
    },
    length: { maximum: 64 },
    allow_nil: true

  private

  def normalize_debug_id
    self.debug_id = debug_id.to_s.downcase if debug_id.present?
  end
end
```

---

## Service Architecture

### Service Objects

#### 1. Event::DebugExtractor
**Extracts debug parameter from event properties**

```ruby
module Event
  class DebugExtractor
    def initialize(event_data)
      @event_data = event_data
    end

    def call
      {
        debug_id: extract_debug_id,
        debug_enabled: debug_id.present?,
        cleaned_properties: remove_debug_param
      }
    end

    private

    # Extract from URL query params (page_view)
    # Extract from event properties (custom events)
    # Validate and normalize
  end
end
```

#### 2. Event::DebugIngestionService
**Wraps standard ingestion with debug extraction**

```ruby
module Event
  class DebugIngestionService
    def initialize(account)
      @account = account
    end

    def call(events_data)
      events_data.map do |event_data|
        debug_data = extract_debug(event_data)
        ingest_with_debug(event_data, debug_data)
      end
    end

    private

    # Extract debug data
    # Merge with event data
    # Delegate to Event::IngestionService
  end
end
```

#### 3. Event::DebugBroadcaster
**Broadcasts processed events to debug channel**

```ruby
module Event
  class DebugBroadcaster
    def initialize(event)
      @event = event
    end

    def call
      return unless event.debug_enabled?

      broadcast_to_channel
    end

    private

    # Format event for broadcast
    # Broadcast via ActionCable
    # Include enrichment data
  end
end
```

#### 4. Event::DebugPresenter
**Formats event for debug console display**

```ruby
module Event
  class DebugPresenter < SimpleDelegator
    def as_json
      {
        id: prefix_id,
        debug_id: debug_id,
        event_type: event_type,
        status: processing_status,
        occurred_at: occurred_at.iso8601,
        enrichment: enrichment_summary,
        properties: formatted_properties,
        metadata: processing_metadata
      }
    end

    def enrichment_summary
      # Extract UTMs, referrer, channel, etc.
      # Format for quick display
    end

    def processing_metadata
      # Processing time, latency, etc.
    end
  end
end
```

#### 5. Events::DebugQuery
**Query object for finding debug events**

```ruby
module Events
  class DebugQuery
    def initialize(account, debug_id)
      @account = account
      @debug_id = debug_id
    end

    def call
      account
        .events
        .debug_enabled
        .by_debug_id(debug_id)
        .order(occurred_at: :desc)
        .limit(1000)
    end

    private

    attr_reader :account, :debug_id
  end
end
```

---

## Controller Design

### DebugConsole::ShowController

```ruby
module DebugConsole
  class ShowController < ApplicationController
    before_action :authenticate_user!

    def show
      @debug_id = params[:id]
      @events = load_events if @debug_id.present?
    end

    private

    def load_events
      Events::DebugQuery
        .new(current_account, params[:id])
        .call
    end
  end
end
```

### DebugConsole::EventsController

```ruby
module DebugConsole
  class EventsController < ApplicationController
    before_action :authenticate_user!

    # GET /debug/events?debug_id=xxx
    def index
      render json: {
        events: debug_events,
        count: debug_events.count
      }
    end

    # GET /debug/events/:id
    def show
      render json: Event::DebugPresenter.new(event).as_json
    end

    # DELETE /debug/events?debug_id=xxx
    def destroy
      delete_debug_session
      head :no_content
    end

    private

    def debug_events
      Events::DebugQuery.new(current_account, params[:debug_id]).call
    end

    def event
      current_account.events.find_by_prefix_id!(params[:id])
    end

    def delete_debug_session
      current_account
        .events
        .by_debug_id(params[:debug_id])
        .delete_all
    end
  end
end
```

---

## Testing Strategy

### Unit Tests

#### Event::DebugExtractor Test
```ruby
class Event::DebugExtractorTest < ActiveSupport::TestCase
  test "extracts debug from URL query params" do
    event_data = {
      event_type: "page_view",
      properties: {
        url: "https://example.com?debug=test-123"
      }
    }

    result = extractor(event_data).call

    assert_equal "test-123", result[:debug_id]
    assert result[:debug_enabled]
  end

  test "extracts debug from custom event properties" do
    event_data = {
      event_type: "signup",
      properties: {
        debug: "test-signup",
        plan: "pro"
      }
    }

    result = extractor(event_data).call

    assert_equal "test-signup", result[:debug_id]
    refute result[:cleaned_properties][:debug]
  end

  test "normalizes debug_id to lowercase" do
    event_data = {
      properties: { debug: "TEST-123" }
    }

    result = extractor(event_data).call

    assert_equal "test-123", result[:debug_id]
  end

  test "handles missing debug parameter" do
    event_data = {
      properties: { url: "https://example.com" }
    }

    result = extractor(event_data).call

    assert_nil result[:debug_id]
    refute result[:debug_enabled]
  end

  test "validates debug_id format" do
    invalid_ids = ["test@123", "test 123", "test.123"]

    invalid_ids.each do |invalid_id|
      event_data = { properties: { debug: invalid_id } }
      result = extractor(event_data).call

      assert_nil result[:debug_id], "Should reject: #{invalid_id}"
    end
  end

  private

  def extractor(event_data)
    Event::DebugExtractor.new(event_data)
  end
end
```

#### Event::DebugBroadcaster Test
```ruby
class Event::DebugBroadcasterTest < ActiveSupport::TestCase
  test "broadcasts debug-enabled event" do
    event = create_debug_event

    assert_broadcasts_on(debug_channel(event)) do
      broadcaster(event).call
    end
  end

  test "does not broadcast non-debug event" do
    event = create_event(debug_enabled: false)

    assert_no_broadcasts do
      broadcaster(event).call
    end
  end

  test "includes enrichment data in broadcast" do
    event = create_debug_event_with_utm

    payload = capture_broadcast(event)

    assert_equal "google", payload[:enrichment][:utm_source]
    assert_equal "paid", payload[:enrichment][:channel]
  end

  private

  def create_debug_event
    events(:debug_page_view)
  end

  def broadcaster(event)
    Event::DebugBroadcaster.new(event)
  end

  def debug_channel(event)
    "debug_#{event.debug_id}"
  end
end
```

### Integration Tests

#### Debug Console Integration Test
```ruby
class DebugConsoleIntegrationTest < ActionDispatch::IntegrationTest
  test "displays debug events in real-time" do
    sign_in users(:one)

    visit debug_console_path(id: "test-123")

    assert_text "Listening for events"

    # Simulate event ingestion
    create_debug_event(debug_id: "test-123")

    # Event should appear in stream
    assert_text "page_view"
    assert_text "utm_source: google"
  end

  test "filters events by type" do
    sign_in users(:one)
    create_debug_events_of_different_types

    visit debug_console_path(id: "test-123")

    select "page_view", from: "Event Type"

    assert_text "page_view"
    refute_text "signup_completed"
  end

  test "expands event to show details" do
    sign_in users(:one)
    event = create_debug_event

    visit debug_console_path(id: event.debug_id)

    click_button "Expand"

    assert_text "UTM Parameters"
    assert_text "Visitor Context"
    assert_text event.visitor_id
  end
end
```

### System Tests (ActionCable)

```ruby
class DebugConsoleSystemTest < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_chrome

  test "receives events via WebSocket" do
    sign_in users(:one)

    visit debug_console_path(id: "test-123")

    # Verify WebSocket connection
    assert_text "🟢 Connected"

    # Trigger event in another thread
    perform_enqueued_jobs do
      Event::IngestionService.new(account).call([
        {
          event_type: "page_view",
          debug: "test-123",
          properties: { url: "https://example.com" }
        }
      ])
    end

    # Event should appear in real-time
    assert_text "page_view", wait: 2
    assert_text "https://example.com"
  end
end
```

---

## Documentation Checklist

### API Documentation

- [ ] **Debug Parameter Reference**
  - Supported formats
  - Validation rules
  - Examples for page_view and custom events

- [ ] **Debug Console Guide**
  - How to access
  - How to use filters
  - How to interpret enrichment data

- [ ] **Troubleshooting Guide**
  - Common issues and solutions
  - What to do when events don't appear
  - How to validate implementation

### Code Documentation

- [ ] **Service Object Documentation**
  - Purpose and responsibility of each service
  - Input/output contracts
  - Examples

- [ ] **Channel Documentation**
  - How to subscribe to debug channel
  - Message format
  - Security/scoping

- [ ] **Model Documentation**
  - Debug-related fields and indexes
  - Scopes and queries
  - Validation rules

### User Documentation

- [ ] **Quick Start Guide**
  - 3-step process to start debugging
  - Screenshots
  - Video tutorial

- [ ] **Advanced Usage**
  - Filtering and searching
  - Exporting data
  - Sharing debug sessions

- [ ] **Best Practices**
  - Naming debug IDs
  - When to use debug mode
  - Privacy considerations

---

## Success Metrics

### Developer Experience
- Time to first successful debug session < 2 minutes
- 95% of developers can validate implementation without support
- Average debug session duration: 5-10 minutes
- Developer satisfaction score > 4.5/5

### Technical Performance
- Event appears in debug console < 1 second after processing
- WebSocket connection stability > 99.9%
- Debug query performance < 100ms (p95)
- Zero data leaks between accounts

### Adoption
- 80% of new accounts use debug mode during setup
- 50% of developers use debug mode regularly
- Debug feature mentioned in 60% of positive reviews

---

## Privacy & Security

### Multi-Tenancy
- Debug events MUST be scoped to account
- WebSocket channels MUST verify account ownership
- No cross-account debug ID collisions

### Data Retention
- Debug events retained for 90 days
- Auto-purge after 90 days (scheduled job)
- Manual deletion available anytime

### Sensitive Data
- Debug IDs should not contain sensitive info (warn in docs)
- Debug URLs logged but not exposed in UI
- Debug parameters stripped from analytics

### Access Control
- Only authenticated account users can access debug console
- Debug sessions tied to account, not user
- API endpoints require authentication

---

## Edge Cases & Error Handling

### Invalid Debug IDs
- Special characters → reject silently, log warning
- Too long (> 64 chars) → truncate
- Empty string → ignore
- Null/undefined → ignore

### Duplicate Debug IDs
- Same debug_id across multiple events → expected behavior
- Same debug_id across accounts → isolated by account scope
- Debug ID collision → no issue (scoped to account + time)

### WebSocket Failures
- Connection lost → show disconnected status, auto-reconnect
- Reconnect after 1s, 5s, 10s (exponential backoff)
- Missed events during disconnect → load from API on reconnect

### High Volume
- > 1000 events per debug session → paginate, warn user
- Rapid event stream → throttle UI updates to 10/second
- Memory leak → auto-cleanup old events from DOM

### Processing Failures
- Event validation fails → show in debug console with error
- Enrichment fails → show partial data + error
- Event rejected (rate limit) → show rejection reason

---

## Implementation Phases

### Phase 1: Core Infrastructure (Week 1)
- [ ] Add debug columns to events table
- [ ] Implement Event::DebugExtractor service
- [ ] Implement Event::DebugIngestionService
- [ ] Add debug scopes to Event model
- [ ] Write unit tests for extraction and validation

### Phase 2: Debug Console UI (Week 2)
- [ ] Create debug console route and controller
- [ ] Build basic UI (debug ID input, event list)
- [ ] Implement Events::DebugQuery
- [ ] Display events in collapsed card view
- [ ] Add time filters

### Phase 3: Real-Time Streaming (Week 3)
- [ ] Set up ActionCable channel
- [ ] Implement Event::DebugBroadcaster
- [ ] Connect UI to WebSocket
- [ ] Add connection status indicator
- [ ] Handle reconnection logic

### Phase 4: Event Inspector (Week 4)
- [ ] Build expanded event view
- [ ] Implement Event::DebugPresenter
- [ ] Add enrichment breakdown sections
- [ ] Syntax highlighting for JSON
- [ ] Copy to clipboard functionality

### Phase 5: Filters & Search (Week 5)
- [ ] Add event type filter
- [ ] Add status filter
- [ ] Add search by URL/properties
- [ ] Combine filters with AND logic
- [ ] Add reset filters button

### Phase 6: Polish & Documentation (Week 6)
- [ ] Add help content and examples
- [ ] Implement export functionality
- [ ] Add shareable debug links
- [ ] Write user documentation
- [ ] Create video tutorial
- [ ] Add debug alerts/warnings

---

## Future Enhancements

### v2 Features
- **Debug Recording**: Record session replay with debug events
- **Debug Webhooks**: Send debug events to external tools (Slack, Discord)
- **Debug Comparison**: Compare two debug sessions side-by-side
- **Debug Templates**: Pre-configured debug scenarios for common tests
- **Debug Analytics**: Metrics on debug usage patterns

### v3 Features
- **Collaborative Debugging**: Multiple users watch same debug session
- **Debug Assertions**: Define expected outcomes, alert if not met
- **Debug Playback**: Time-travel through debug session
- **Debug Snapshot**: Save state of debug session for later review
- **Integration Testing**: Automated tests using debug mode

---

## Open Questions

1. **Retention Policy**: 90 days enough? Configurable per account?
2. **Rate Limiting**: Should debug events count toward rate limits?
3. **Performance**: What's acceptable latency for debug broadcast?
4. **Pricing**: Debug mode free for all plans or premium feature?
5. **Analytics Exclusion**: Always exclude or make optional?
6. **Debug ID Sharing**: Should debug sessions be shareable across teams?
7. **Notifications**: Email/Slack when debug event fails?

---

## References

### Similar Implementations
- **Stripe**: Request logs with request ID filter
- **Segment**: Debugger with live event stream
- **PostHog**: Session replay with event timeline
- **Mixpanel**: Live view with event inspector

### Technical Resources
- ActionCable Guide: https://guides.rubyonrails.org/action_cable_overview.html
- Turbo Streams: https://turbo.hotwired.dev/handbook/streams
- WebSocket Best Practices
- Real-time Rails Patterns

---

**End of Specification**

*This spec should be reviewed and validated before implementation begins. All sections should be approved by product, engineering, and design stakeholders.*
