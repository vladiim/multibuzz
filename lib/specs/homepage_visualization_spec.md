# Homepage Visualization Specification

**Status**: Draft - Awaiting Direction
**Last Updated**: 2025-11-29
**Epic**: E1S4 - Homepage Update

---

## Core Requirements

1. **Interactive model switcher** - User selects attribution model, sees credit redistribute
2. **Animated events** - Touchpoints animate in, feel alive and engaging
3. **Clear "aha moment"** - Switching models shows dramatically different credit allocation

---

## Attribution Animation Concepts

All concepts include:
- Model selector: `[First Touch] [Last Touch] [Linear] [Time Decay] [U-Shaped]`
- Animated transitions when model changes
- Revenue amounts that visibly redistribute

---

### Concept A: Particle Flow

**Visual**: Events are glowing particles that flow along a path toward conversion

```
                                                    ┌──────────┐
   ○ ──────────○──────────○──────────○─────────────▶│CONVERSION│
   │           │          │          │              │   $99    │
 Google     Facebook    Email     Direct            └──────────┘
  (particle)  (particle) (particle) (particle)
```

**Animation**:
- Particles continuously flow from left to right (like a river of events)
- Each particle has channel color (Google=red, FB=blue, Email=yellow, etc.)
- When user switches model, particles "glow" at different intensities
- First Touch: First particle blazes bright, others dim
- Last Touch: Last particle blazes, others dim
- Linear: All particles glow equally
- Credit bars below pulse as they update

**Feel**: Mesmerizing, shows continuous flow of customer journeys

---

### Concept B: Pinball / Bounce Path

**Visual**: A visitor "ball" bounces through touchpoints like a pinball machine

```
                    ┌─────┐
        ┌──────────▶│ FB  │──────────┐
        │           └─────┘          │
   ┌────┴──┐                    ┌────▼────┐
   │Google │                    │  Email  │
   │ Ads   │                    │         │
   └───────┘                    └────┬────┘
                                     │
                                     ▼
                              ┌──────────────┐
                              │  CONVERSION  │
                              │     $99      │
                              └──────────────┘
```

**Animation**:
- Visitor ball drops in from top
- Bounces off Google → FB → Email → Conversion
- Each bounce creates a ripple/glow effect
- On conversion: explosion of confetti/particles
- Credit flows back to each touchpoint it hit
- Model switch = credit amounts animate to new values

**Feel**: Playful, game-like, memorable

---

### Concept C: Timeline with Pulse

**Visual**: Horizontal timeline, touchpoints pulse as visitor progresses

```
 Day 1              Day 4              Day 6              Day 8
   │                  │                  │                  │
   ▼                  ▼                  ▼                  ▼
 ╭───╮    ─ ─ ─ ─   ╭───╮    ─ ─ ─ ─   ╭───╮    ─ ─ ─ ─   ╭───╮
 │ G │    ════════▶ │FB │    ════════▶ │ ✉ │    ════════▶ │ $ │
 ╰───╯              ╰───╯              ╰───╯              ╰───╯
   │                  │                  │                  │
   ▼                  ▼                  ▼                  ▼
 ┌────┐            ┌────┐            ┌────┐
 │$33 │            │$33 │            │$33 │
 │████│            │████│            │████│
 └────┘            └────┘            └────┘
```

**Animation**:
- Visitor icon travels along timeline (like a progress indicator)
- Each touchpoint pulses/glows as visitor passes through
- Connection lines draw with animated dashes
- Conversion triggers celebration
- Credit bars grow from 0 simultaneously
- Model switch: bars animate to new heights, $ amounts count up/down

**Model switching effect**:
- First Touch: Google bar grows to 100%, others shrink to 0%
- Last Touch: Email bar grows to 100%, others shrink
- Linear: All bars equalize to ~33%
- Time Decay: Bars scale proportionally (Email biggest, Google smallest)

**Feel**: Professional, clear, tells a story

---

### Concept D: Sankey / Flow Diagram

**Visual**: Revenue flows from conversion back to channels like a Sankey diagram

```
                              ┌────────────┐
                              │ CONVERSION │
                              │    $99     │
                              └─────┬──────┘
                                    │
                 ┌──────────────────┼──────────────────┐
                 │                  │                  │
            ╔════╧════╗        ╔════╧════╗        ╔════╧════╗
            ║ Google  ║        ║Facebook ║        ║  Email  ║
            ║   $33   ║        ║   $33   ║        ║   $33   ║
            ╚═════════╝        ╚═════════╝        ╚═════════╝
```

**Animation**:
- Conversion amount appears, money "drips" down
- Flow lines animate like liquid pouring
- Each channel "fills up" with its credit
- Model switch = liquid redistributes (empties from some, fills others)

**Model switching effect**:
- Dramatic visual as $99 flows entirely to one channel (First/Last Touch)
- Or splits evenly (Linear)
- Shows the "why it matters" - same conversion, wildly different channel credit

**Feel**: Data-viz forward, satisfying "liquid" animations

---

### Concept E: Orbit / Solar System

**Visual**: Conversion is the "sun", touchpoints orbit around it

```
                    Google ○
                         ╲
                          ╲
            Email ○ ───────● CONVERSION ─────── ○ Facebook
                          ╱    $99
                         ╱
                   Direct ○
```

**Animation**:
- Touchpoints slowly orbit the conversion
- Orbit radius = credit amount (closer = more credit)
- Model switch = touchpoints animate to new orbits
- First Touch: Google pulls in close, others drift far
- Last Touch: Email pulls in close
- Linear: All equidistant
- Connecting lines glow to show the journey path

**Feel**: Unique, cosmic, memorable

---

## My Recommendation

**Concept C (Timeline with Pulse)** or **Concept D (Sankey Flow)**

- **Timeline**: Best for storytelling ("here's the journey")
- **Sankey**: Best for impact ("look how credit shifts")

Could even combine: Timeline shows the journey FIRST, then transitions to Sankey view when showing attribution.

---

## Model Switcher Design

```
┌─────────────────────────────────────────────────────────────────┐
│  Attribution Model:                                              │
│                                                                  │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌──────────────┐ │
│  │First Touch │ │Last Touch  │ │  Linear    │ │ Time Decay   │ │
│  │            │ │            │ │  ●         │ │              │ │
│  └────────────┘ └────────────┘ └────────────┘ └──────────────┘ │
│                                                                  │
│  Linear: Equal credit to all touchpoints in the journey         │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

- Pill/toggle button style
- Selected model highlighted
- Brief description below explains the model
- Switching triggers smooth animation (not instant snap)

---

## Questions

1. **Which concept resonates?** A (Particle), B (Pinball), C (Timeline), D (Sankey), E (Orbit)?

2. **Combine concepts?** e.g., Timeline journey → Sankey credit distribution?

3. **Loop or trigger?** Should animation loop continuously, or play once then allow replay?

4. **Mobile**: Simplified static version, or attempt responsive animation?

---

## NEW SECTION: Attribution Model Editor Showcase

**Status**: TODO
**Position**: After Features section, before SDKs

### The Value Proposition

Every other attribution tool is a black box. You pick a model, you get a number, and you have no idea how it was calculated. Multibuzz is different—we show you exactly how credit is assigned, and let you change it.

### Headline & Messaging

**Title**: No More Black Boxes

**Subtitle**: "Your competitors are stuck with one-size-fits-all attribution. You're not."

**Supporting Copy Ideas**:
- "See exactly how credit flows to each channel. Customize it in minutes."
- "Finally understand why Facebook gets 40% and Google gets 10%."
- "Stop trusting algorithms you can't see. Start using models you control."

### Visual Layout

Vertical tabs on the left (model selector) + code/preview panel on the right.

```
┌─────────────────────────────────────────────────────────────────────┐
│                                                                      │
│                     No More Black Boxes                              │
│     Your competitors are stuck with one-size-fits-all attribution.   │
│                         You're not.                                  │
│                                                                      │
│   ┌────────┬──────────────────────────────────────────────────────┐ │
│   │        │                                                       │ │
│   │  [⚡]  │  ┌─────────────────────────────────────────────────┐ │ │
│   │ First  │  │                                                  │ │ │
│   │ Touch  │  │  within_window 30.days do                        │ │ │
│   │        │  │    apply 1.0, to: touchpoints.first              │ │ │
│   │  [🎯]  │  │  end                                             │ │ │
│   │ Last   │  │                                                  │ │ │
│   │ Touch  │  └─────────────────────────────────────────────────┘ │ │
│   │        │                                                       │ │
│   │  [═]   │  ─────────────────────────────────────────────────── │ │
│   │Linear  │                                                       │ │
│   │        │   First Touch Attribution                             │ │
│   │  [⏱]   │   Give 100% credit to the channel that started       │ │
│   │ Time   │   the customer journey.                               │ │
│   │ Decay  │                                                       │ │
│   │        │   Best for: Brand awareness campaigns, top-of-funnel  │ │
│   │  [∪]   │   measurement, understanding discovery channels.      │ │
│   │U-Shape │                                                       │ │
│   │        │                                                       │ │
│   └────────┴──────────────────────────────────────────────────────┘ │
│                                                                      │
│                    [See How It Works →]                              │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Model Tabs with Icons

| Model | Icon | Marketing Description |
|-------|------|----------------------|
| First Touch | ⚡ | Credit the channel that started it all |
| Last Touch | 🎯 | Credit the channel that closed the deal |
| Linear | ═ | Split credit equally across every touchpoint |
| Time Decay | ⏱ | More credit to recent interactions |
| U-Shaped | ∪ | Heavy credit to first and last, less to middle |
| Custom | ✏️ | Build your own model (teaser for paid) |

### Key Differentiators to Emphasize

1. **Transparency**: "This is the actual code. No hidden formulas, no proprietary algorithms."
2. **Control**: "Don't like how credit is assigned? Change it in 30 seconds."
3. **Flexibility**: "Match attribution to your actual business, not someone else's assumptions."
4. **No Vendor Lock-in**: "Export your models. Own your logic."

### Model Descriptions (Marketing-Focused)

**First Touch**
> Give 100% credit to the channel that introduced the customer to your brand. Perfect for measuring brand awareness and discovery.

**Last Touch**
> Give 100% credit to the final touchpoint before conversion. See which channels are closing deals.

**Linear**
> Split credit equally across every interaction. Fair, simple, and easy to explain to stakeholders.

**Time Decay**
> Recent touchpoints get more credit than earlier ones. Ideal when you want to weight what happened closest to conversion.

**U-Shaped**
> 40% to first touch, 40% to last touch, 20% split across the middle. Rewards both discovery and conversion.

**Custom**
> Your business isn't average—why should your attribution be? Create models that match your actual customer journey.

### Interaction Flow

1. User lands on section, First Touch is selected by default
2. Click different model tab → code updates, description updates
3. Code is syntax-highlighted for readability (keywords in pink, numbers in orange)
4. Below code: Plain-English description + "Best for:" use cases
5. CTA: "See How It Works" or "Try It Free"

### Mobile Design

- Horizontal scrolling tabs (icons only)
- Stacked layout: tabs → code → description
- Tap tab to switch model

### Animation Considerations

Keep it simple—the code itself is the hero. Consider:
- Subtle fade transition between models
- Highlight effect on active tab
- Avoid distracting animations that compete with the message

### Success Metrics

- Section engagement time
- Tab interactions (which models are users exploring?)
- Clicks through to signup from this section
- Scroll continuation past section
