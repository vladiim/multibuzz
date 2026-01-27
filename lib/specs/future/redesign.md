# mbuzz Retro 70s Redesign

**Status:** Exploratory Mockups
**Created:** 2026-01-17
**V1 Mockup URLs:** `/mockups/retro/homepage`, `/mockups/retro/demo`
**V2 Mockup URLs:** `/mockups/retrov2/homepage`, `/mockups/retrov2/demo`

---

## Design Brief

### Project Overview

Reimagining mbuzz.co as a bold, nostalgic alternative to sterile SaaS platforms. Drawing from the Retro 70s Vibe (Energetic Nostalgia), the design evokes warm, groovy 1970s aesthetics—think vintage ads, old-school tech manuals, analog computing vibes, and punchy energy.

This isn't pixelated 8-bit retro; it's earthy, human, and approachable, like rediscovering a trusted tool from the disco era. The goal is to make mbuzz feel authentic, rebellious against black-box analytics, and empowering for technical teams.

### Key Brand Elements

| Element | Direction |
|---------|-----------|
| Core Message | "Stop renting your attribution. Own it." |
| Target Audience | Technical teams (devs, marketers) frustrated with GA4, ad platforms, and enterprise tools |
| Tone | Confident, witty, anti-corporate. Casual language (e.g., "Platforms grade their own homework") |
| Differentiation | Warm nostalgia—earthy tones, organic shapes, subtle textures for a "vintage manual" feel |

### What to Avoid

- Modern minimalism, blues/grays, or "another fucking SaaS app" sterility
- Pixel art, space themes, or overly quirky illustrations
- PostHog's style (quirky/pixelated)

### References & Inspiration

- **70s Ads:** Coca-Cola, IBM posters—bold type, warm colors
- **Tech Manuals:** Early Apple/IBM guides—monospace text, diagrams
- **Modern Twists:** Retrofuturism, 70s-inspired brands (e.g., Burger King retro rebrands)

---

## Color Palette

| Name | HEX | Usage |
|------|-----|-------|
| Primary Red | `#D93F2B` | Logo base, CTAs, highlights |
| Accent Orange | `#F2A950` | Accents, icons, borders |
| Earthy Brown | `#5A3D2B` | Backgrounds, dividers, text accents |
| Muted Green | `#75C8AE` | Charts, success states, subtle accents |
| Off-White Neutral | `#FFECB4` | Main backgrounds, cards |
| Deep Accent | `#4D2C1A` | Footers, shadows, emphasis |

### Extended Palette (Implementation)

```css
--retro-red: #D93F2B;
--retro-orange: #F2A950;
--retro-brown: #5A3D2B;
--retro-green: #75C8AE;
--retro-cream: #FFECB4;
--retro-deep: #4D2C1A;
--retro-red-light: #e85d4a;
--retro-orange-light: #f5bc73;
--retro-brown-light: #7a5d4b;
```

---

## Typography

### Font Pairings

| Role | Font | Notes |
|------|------|-------|
| Display/Headings | **Cooper BT** (spec) / **Bree Serif** (implementation) | Rounded, bubbly serif with 70s flair |
| Body/Subheadings | **Roboto Mono** | Monospaced sans-serif, nods to vintage code terminals |

### Implementation Choice: Bree Serif

Cooper BT is not available on Google Fonts. We chose **Bree Serif** as the closest available alternative:
- Similar rounded, friendly character
- Available via Google Fonts (no licensing issues)
- Works well at display sizes

**Alternative options to explore:**
- Self-host actual Cooper BT (requires license purchase)
- Alfa Slab One (more condensed, bolder)
- Coustard (similar warmth)

### Type Scale

| Element | Size | Weight |
|---------|------|--------|
| H1 (Hero) | 48-72px | Regular |
| H2 (Section) | 32-48px | Regular |
| H3 (Card Title) | 24-32px | Regular |
| Body | 16px | Regular |
| Subheads | 18-24px | Medium |
| Small/Labels | 12-14px | Regular/Medium |

---

## Visual Style Decisions

### Textures & Backgrounds

1. **Paper Grain Texture**
   - Subtle SVG noise filter at 3% opacity
   - Applied to body via `.texture-paper` class

2. **Groovy Wave Background**
   - Radial gradients creating soft, organic shapes
   - Green at 20% 80%, Orange at 80% 20%, Red at center
   - Low opacity (8-15%) to avoid overwhelming content

3. **Hero Background**
   - Linear gradient from cream to slightly warmer cream
   - Decorative radial gradients for depth

### Components Implemented

#### Buttons (`.btn-retro`)
- Chunky 3px border with drop shadow (4px 4px)
- Shadow shifts on hover (2px 2px) for tactile feel
- Border radius: 8px
- Uses display font (Bree Serif)

#### Cards (`.card-retro`)
- 3px brown border
- 6px drop shadow
- 12px border radius
- Paper-colored background

#### Code Blocks (`.code-retro`)
- Deep accent background
- Syntax highlighting using palette colors
- Orange for keywords, green for strings, red for methods

#### Tables (`.table-retro`)
- Rounded corners via border-collapse: separate
- Alternating row colors (cream/light green)
- Brown headers with cream text

### Decorative Elements

1. **Wave Divider**
   - Gradient bar: orange → red → brown
   - 4px height, rounded ends
   - Used between major sections

2. **Decorative Circles**
   - Positioned absolutely
   - Orange or green border, no fill
   - 30% opacity
   - Creates depth without distraction

3. **Badges/Pills**
   - "Live" badge: green background
   - "Coming Soon" badge: orange background
   - Both have brown border

---

## Animations Implemented

### Page Load

1. **Buzz-In Effect** (`.animate-buzz-in`)
   - Horizontal micro-shake (3px → -3px → 2px → -2px → 0)
   - 0.5s duration
   - Used on hero elements

2. **Fade Up** (`.animate-fade-up`)
   - Opacity 0→1, translateY 20px→0
   - 0.6s ease-out
   - Staggered delays (100-500ms)

### Interactions

1. **Button Hover**
   - Shadow reduction (4px → 2px)
   - Position shift (2px, 2px)
   - Color change (red → orange)

2. **Card Hover**
   - Subtle lift (-translate-y-1)
   - Icon rotation (3 degrees)

### Dashboard Specific

1. **Counter Animation**
   - Fade in with slight Y offset
   - Random delay for organic feel

2. **Chart Updates**
   - Bar height transitions (0.5s)
   - Triggered by model selector change

---

## Page Structure

### Homepage Sections

1. **Navigation** - Sticky brown bar with logo, links, CTA
2. **Hero** - Main headline, subhead, CTA buttons, quick stats
3. **No More Black Boxes** - Code example + attribution visualization
4. **Why Attribution is Broken** - 4-card problem grid
5. **Accurate. Affordable. Yours.** - 3-feature highlight
6. **Channel Performance** - Bar chart visualization
7. **Everything You Need** - 6-feature grid
8. **Plug & Play SDKs** - SDK badges carousel
9. **Pricing** - 3-tier pricing table
10. **Comparison Table** - vs GA4 vs Enterprise
11. **Final CTA** - Red banner with signup
12. **Footer** - Links, logo, copyright

### Demo Dashboard Sections

1. **Demo Banner** - "Sample Data" indicator
2. **Header** - Logo + back link
3. **Controls** - Date range, attribution model selector
4. **Stats Row** - 4 KPI cards
5. **Charts Grid** - Bar chart + pie chart
6. **Customer Journey** - 5-step timeline
7. **Recent Conversions** - Table with sample data
8. **Bottom CTA** - Signup prompt
9. **Footer** - Minimal

---

## Interactive Features (Demo)

### Attribution Model Switcher

JavaScript-driven switcher that updates:
- Bar chart heights
- Journey step credit percentages
- (Future: pie chart segments)

**Models available:**
- Linear (default)
- First Touch
- Last Touch
- Time Decay
- Position Based

### Data Sets

```javascript
const attributionData = {
  linear: {
    bars: { paid_search: 85, email: 72, organic_social: 58, direct: 45, referral: 32 },
    journey: { first: '20%', second: '20%', third: '20%', fourth: '20%' }
  },
  first: {
    bars: { paid_search: 95, email: 40, organic_social: 35, direct: 20, referral: 10 },
    journey: { first: '100%', second: '0%', third: '0%', fourth: '0%' }
  },
  // ... etc
};
```

---

## Implementation Files

| File | Purpose |
|------|---------|
| `app/controllers/mockups_controller.rb` | Admin-only access control |
| `app/views/layouts/mockups/retro.html.erb` | Custom layout with all CSS |
| `app/views/mockups/retro_homepage.html.erb` | Homepage mockup |
| `app/views/mockups/retro_demo.html.erb` | Demo dashboard mockup |
| `config/routes.rb` | Routes under `/mockups/retro/*` |

### Access Control

```ruby
def require_admin_access
  return if Rails.env.development?
  return if logged_in? && current_user&.admin?
  render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
end
```

---

## Future Refinement Ideas

### Typography
- [ ] Evaluate purchasing Cooper BT license for production
- [ ] Test other Cooper-like alternatives (Coustard, Alfa Slab One)
- [ ] Consider variable font for more weight options

### Visual Polish
- [ ] Add more subtle textures (wood grain, paper grain variations)
- [ ] Create custom icon set in retro style
- [ ] Add vintage-style illustrations (hand-drawn charts, diagrams)
- [ ] Explore halftone/dot patterns for backgrounds

### Animations
- [ ] Add scroll-triggered animations (elements animate as they enter viewport)
- [ ] Parallax scrolling on hero background
- [ ] Chart bars "grow" animation on page load
- [ ] Flip-counter style number animations

### Interactive Demo
- [ ] Make pie chart update with model changes
- [ ] Add more journey examples
- [ ] Implement date range filtering visualization
- [ ] Add "live" counter that ticks up periodically

### Content
- [ ] Refine copy to be more punchy/witty
- [ ] Add testimonials section with retro styling
- [ ] Create "How It Works" diagram
- [ ] Add changelog/updates section

### Technical
- [ ] Extract CSS to separate stylesheet
- [ ] Create Stimulus controllers for interactions
- [ ] Add reduced-motion media query support
- [ ] Performance audit (font loading, image optimization)

---

## Design Principles to Maintain

1. **Warm over cold** - No blues/grays, always earthy tones
2. **Tactile over flat** - Shadows, borders, textures
3. **Human over corporate** - Casual language, organic shapes
4. **Transparent over mysterious** - Show the data, explain the logic
5. **Playful over serious** - But not childish or gimmicky
6. **Vintage over retro-kitsch** - 70s ads, not 80s arcade

---

## Notes

- The mockups are intentionally self-contained (all CSS inline in layout)
- This allows rapid iteration without affecting production styles
- When ready to productionize, CSS should be extracted to proper asset pipeline
- Consider creating a Tailwind plugin for the retro color palette

---

# V2: Enhanced Retro (January 2026)

## V1 Feedback Summary

**Overall Score: 7/10** - Strong foundation, but room to amp up the energetic nostalgia.

### Strengths Identified
- Warm, nostalgic energy with earthy tones
- Good use of rounded elements and punchy buttons
- Effective use of Primary Red for CTAs
- Consistent color palette without cold blues/grays
- Approachable, anti-sterile SaaS feel

### Areas for Improvement

1. **Typography**: Body text used standard sans-serif instead of Roboto Mono
2. **Green Color**: Teal leaned too cool; needed warmer avocado-like hue
3. **Textures**: Missing paper grain, wood overlays, film grain
4. **Motifs**: Lacking circuit boards, starbursts, buzzing bee icons
5. **Backgrounds**: Plain pale yellow missing depth and collage elements
6. **Layouts**: Too grid-based; needed more asymmetry and organic flow
7. **Animations**: Needed more pronounced buzz effects, tick counters
8. **Deep Accent**: Underused (#4D2C1A for shadows/footers)

---

## V2 Changes Implemented

### Color Palette Updates

```css
/* V2: Warmer avocado green instead of cool teal */
--retro-green: #8B9A6D;
--retro-green-light: #A4B587;
--retro-green-dark: #6B7A4D;

/* V2: Additional warmth */
--retro-mustard: #C9A227;
--retro-rust: #B5503C;
--retro-tan: #D4B896;
```

### Typography Fix

**V1 Issue:** Body text used default sans-serif
**V2 Fix:** Roboto Mono applied to ALL body text, not just code blocks

```css
body {
  font-family: 'Roboto Mono', ui-monospace, monospace;
  letter-spacing: 0.02em;
  line-height: 1.7;
}
```

### Enhanced Textures

1. **Paper Grain** - Increased opacity (3% → 4%), more octaves
2. **Film Grain Overlay** - Fixed position, 3% opacity for vintage feel
3. **Wood Panel Texture** - Subtle vertical lines at 2-3% opacity
4. **Graph Paper** - 20px grid for dashboard backgrounds
5. **Circuit Board Pattern** - SVG pattern for tech sections

### New Decorative Elements

1. **Starbursts** (`.starburst`)
   - Mustard yellow 10-point star
   - Applied to CTAs and badges
   - Small variant for subtle accents

2. **Buzzing Bee Icon** (`.icon-bee`)
   - SVG bee with subtle buzz animation
   - Used in logo area and section headers
   - 0.3s shake animation loop

3. **Analog Dial Icons** (`.icon-dial`)
   - CSS-only dial with rotating needle
   - Variable angle via `--dial-angle`
   - Used for feature cards and stats

4. **Wavy Dividers** (`.wave-divider-wavy`)
   - SVG wave pattern instead of flat bar
   - 30px height with layered waves
   - Brown/deep accent colors

5. **Circuit Pattern** (`.pattern-circuit`)
   - SVG grid with connection nodes
   - 10% opacity overlay for tech sections
   - Light version for dark backgrounds

### Layout Improvements

1. **Asymmetric Offsets**
   ```css
   .offset-up { transform: translateY(-8px); }
   .offset-left { transform: translateX(-8px); }
   .tilt-left { transform: rotate(-1deg); }
   .tilt-right { transform: rotate(1deg); }
   ```

2. **Generous Padding** - Increased section padding to 96px (py-24)

3. **Magazine-Like Flow** - Alternating tilts on cards, staggered stats

### Enhanced Animations

1. **Wave-In Effect** (`.animate-wave-in`)
   - Combines Y translation with subtle rotation
   - 0.8s duration with overshoot

2. **Tick Counter Animation**
   - Numbers slide up into view
   - Staggered timing per digit

3. **Pulse Glow** (`.animate-pulse-glow`)
   - Expanding green ring on live elements
   - 2s infinite loop

4. **Enhanced Buzz-In**
   - More pronounced shake (4px vs 3px)
   - 0.6s duration with more keyframes

5. **Reduced Motion Support**
   ```css
   @media (prefers-reduced-motion: reduce) {
     .animate-buzz-in, .animate-wave-in { animation: none; }
   }
   ```

### Component Enhancements

#### Buttons
- Gradient backgrounds (red → rust)
- Inner highlight for 3D effect
- Active state with deeper shadow shift

#### Cards
- Gradient backgrounds (cream → cream-dark)
- Larger shadows (7px)
- Circuit pattern overlay option

#### Code Blocks
- CRT scanline effect overlay
- Deeper gradient background
- Inset shadow for depth

#### Tables
- Enhanced header gradient
- Larger shadows (5px)
- 14px border radius

---

## V2 Implementation Files

| File | Purpose |
|------|---------|
| `app/views/layouts/mockups/retrov2.html.erb` | Enhanced V2 layout |
| `app/views/mockups/retrov2_homepage.html.erb` | V2 homepage |
| `app/views/mockups/retrov2_demo.html.erb` | V2 demo dashboard |

---

## V2 vs V1 Comparison

| Aspect | V1 | V2 |
|--------|----|----|
| Body font | Sans-serif | Roboto Mono |
| Green | Cool teal (#75C8AE) | Warm avocado (#8B9A6D) |
| Textures | Paper grain only | Paper + film + wood + circuit |
| Decorations | Circles only | Starbursts, bees, dials, waves |
| Shadows | 4-6px | 5-7px with gradients |
| Layouts | Symmetric grid | Asymmetric with tilts/offsets |
| Animations | Basic fade/buzz | Wave-in, tick, pulse-glow |
| Dashboard BG | Plain | Graph paper texture |

---

## Remaining V2 Refinements

### Still To Do
- [ ] Add parallax scrolling on hero collage
- [ ] Implement scroll-triggered animations (IntersectionObserver)
- [ ] Create custom retro illustration set
- [ ] Add testimonials section
- [ ] Mobile-specific layout adjustments
- [ ] Performance optimization (lazy load textures)

### Feedback to Address in V3
- Consider adding vintage photo/ad collage in hero
- Explore halftone dot patterns for images
- Add more personality to empty states
- Consider animated bee mascot for loading states
