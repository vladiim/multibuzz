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
