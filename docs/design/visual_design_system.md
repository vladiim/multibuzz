# Multibuzz Visual Design System

**Inspiration**: Attio's clean, minimal, data-forward aesthetic with white-first approach

---

## Architecture Principles

### Separation of Concerns

**CRITICAL**: Never mix styles or scripts with HTML templates.

```ruby
# ❌ BAD - Inline styles and scripts
<div style="color: red;">
<div onclick="doThing()">
<style>.foo { color: red; }</style>
<script>alert('bad');</script>

# ✅ GOOD - Separated concerns
<div class="text-error">
<div data-action="thing">
```

### Stylesheet Organization

**Structure**: Follow ITCSS (Inverted Triangle CSS) methodology

```
app/assets/stylesheets/
├── application.css          # Manifest file
├── config/
│   ├── variables.css       # CSS custom properties (colors, spacing, etc)
│   └── tailwind.config.js  # Tailwind configuration
├── base/
│   ├── reset.css           # Normalize/reset styles
│   └── typography.css      # Base typography styles
├── components/
│   ├── buttons.css         # Button variants
│   ├── cards.css           # Card components
│   ├── forms.css           # Form inputs, labels
│   ├── tables.css          # Data tables
│   ├── badges.css          # Status badges
│   └── navigation.css      # Nav, breadcrumbs
├── layouts/
│   ├── header.css          # Site header
│   ├── footer.css          # Site footer
│   ├── sidebar.css         # Dashboard sidebar
│   └── grid.css            # Grid systems
├── pages/
│   ├── home.css            # Homepage-specific styles
│   ├── dashboard.css       # Dashboard-specific styles
│   └── auth.css            # Login/signup pages
└── utilities/
    ├── animations.css      # Keyframe animations
    └── helpers.css         # Utility classes
```

### Naming Conventions

**Use BEM (Block Element Modifier) for component classes:**

```css
/* Block */
.card { }

/* Element */
.card__header { }
.card__body { }
.card__footer { }

/* Modifier */
.card--elevated { }
.card--interactive { }
.card__header--large { }
```

**For page-specific styles, use namespaced classes:**

```css
/* Homepage */
.home-hero { }
.home-features { }
.home-attribution-flow { }

/* Dashboard */
.dashboard-stats { }
.dashboard-chart { }

/* Auth pages */
.auth-form { }
.auth-card { }
```

### Import Order in application.css

```css
/*
 * Application Stylesheet Manifest
 * Import order matters: general → specific
 */

/* 1. Configuration & Variables */
@import "config/variables";

/* 2. Base Styles */
@import "base/reset";
@import "base/typography";

/* 3. Tailwind (if using) */
@import "tailwindcss/base";
@import "tailwindcss/components";
@import "tailwindcss/utilities";

/* 4. Layout */
@import "layouts/header";
@import "layouts/footer";
@import "layouts/sidebar";
@import "layouts/grid";

/* 5. Components (alphabetical) */
@import "components/badges";
@import "components/buttons";
@import "components/cards";
@import "components/forms";
@import "components/navigation";
@import "components/tables";

/* 6. Pages (alphabetical) */
@import "pages/auth";
@import "pages/dashboard";
@import "pages/home";

/* 7. Utilities */
@import "utilities/animations";
@import "utilities/helpers";
```

### JavaScript Organization

**Structure**: Stimulus controllers for interactivity

```
app/javascript/
├── application.js           # Entry point
├── controllers/
│   ├── index.js            # Controller registry
│   ├── animation_controller.js
│   ├── dropdown_controller.js
│   ├── modal_controller.js
│   └── clipboard_controller.js
└── lib/
    └── utilities.js        # Shared helper functions
```

**Use Stimulus data attributes for behavior:**

```html
<!-- ✅ GOOD - Declarative, separated -->
<div data-controller="dropdown">
  <button data-action="click->dropdown#toggle">Menu</button>
  <div data-dropdown-target="menu">...</div>
</div>

<!-- ❌ BAD - Inline handlers -->
<div onclick="toggleDropdown()">
```

---

## Design Philosophy

Multibuzz uses a **white foundation** with **black text hierarchy** and **strategic blue highlights** to create a clean, professional interface that emphasizes data clarity and lets content breathe.

Key principles:
- **White-first**: Clean white backgrounds as primary foundation
- **Minimal color**: Monochrome with blue for emphasis and interaction
- **Data-forward**: Clean layouts with structured information (tables, cards, lists)
- **Generous spacing**: Let content breathe
- **Flow visualization**: Subtle animations showing multi-touch attribution flowing into unified insights

---

## Color Palette

### Base Colors
```css
/* Neutrals - Foundation */
--white: #ffffff
--gray-50: #f9fafb
--gray-100: #f3f4f6
--gray-200: #e5e7eb
--gray-300: #d1d5db
--gray-400: #9ca3af
--gray-500: #6b7280
--gray-600: #4b5563
--gray-700: #374151
--gray-800: #1f2937
--gray-900: #111827
--black: #000000

/* Semantic Usage */
--bg-primary: var(--white)
--bg-secondary: var(--gray-50)
--bg-tertiary: var(--gray-100)

--text-primary: var(--gray-900)
--text-secondary: var(--gray-600)
--text-tertiary: var(--gray-500)

--border-subtle: var(--gray-100)
--border-default: var(--gray-200)
--border-emphasis: var(--gray-300)
```

### Accent Colors
```css
/* Blue - Primary Brand & Interactive */
--blue-600: #2563eb
--blue-500: #3b82f6
--blue-400: #60a5fa
--blue-50: #eff6ff

/* Gradient for highlights (subtle) */
--gradient-primary: linear-gradient(135deg, #3b82f6 0%, #60a5fa 100%)

/* Channel Colors for Attribution Flow */
--channel-google: #ea4335
--channel-facebook: #1877f2
--channel-linkedin: #0a66c2
--channel-email: #10b981
--channel-direct: #8b5cf6
--channel-organic: #f59e0b
```

### Status & Feedback
```css
--success: #10b981
--success-bg: #d1fae5
--warning: #f59e0b
--warning-bg: #fef3c7
--error: #ef4444
--error-bg: #fee2e2
--info: #3b82f6
--info-bg: #dbeafe
```

---

## Typography

### Font Stack
```css
font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', sans-serif;
```

### Scale & Hierarchy
```css
/* Headings */
--text-6xl: 3.75rem / 1.1   /* 60px - Hero titles */
--text-5xl: 3rem / 1.1      /* 48px - Page titles */
--text-4xl: 2.25rem / 1.2   /* 36px - Section headers */
--text-3xl: 1.875rem / 1.3  /* 30px - Card titles */
--text-2xl: 1.5rem / 1.3    /* 24px - Subsections */
--text-xl: 1.25rem / 1.4    /* 20px - Large body */

/* Body */
--text-base: 1rem / 1.5     /* 16px - Default body */
--text-sm: 0.875rem / 1.5   /* 14px - Small body, table text */
--text-xs: 0.75rem / 1.5    /* 12px - Captions, labels */

/* Weights */
--font-normal: 400
--font-medium: 500
--font-semibold: 600
--font-bold: 700
```

---

## Spacing & Layout

### Spacing Scale
```css
--space-1: 0.25rem    /* 4px */
--space-2: 0.5rem     /* 8px */
--space-3: 0.75rem    /* 12px */
--space-4: 1rem       /* 16px */
--space-5: 1.25rem    /* 20px */
--space-6: 1.5rem     /* 24px */
--space-8: 2rem       /* 32px */
--space-10: 2.5rem    /* 40px */
--space-12: 3rem      /* 48px */
--space-16: 4rem      /* 64px */
--space-20: 5rem      /* 80px */
--space-24: 6rem      /* 96px */
--space-32: 8rem      /* 128px */
```

### Grid System
```css
/* 12-column responsive grid */
.container {
  max-width: 1280px;
  margin: 0 auto;
  padding: 0 var(--space-6);
}

.grid {
  display: grid;
  grid-template-columns: repeat(12, 1fr);
  gap: var(--space-6);
}

/* Responsive breakpoints */
@media (max-width: 1024px) {
  .container {
    padding: 0 var(--space-4);
  }
}
```

---

## Component Patterns

### Cards
```css
.card {
  background: var(--white);
  border: 1px solid var(--border-default);
  border-radius: 8px;
  padding: var(--space-6);
  transition: all 150ms ease;
}

.card:hover {
  border-color: var(--border-emphasis);
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1), 0 1px 2px rgba(0, 0, 0, 0.06);
}

/* Elevated card for emphasis */
.card-elevated {
  box-shadow: 0 4px 6px rgba(0, 0, 0, 0.05), 0 1px 3px rgba(0, 0, 0, 0.1);
}
```

### Tables (Data-Forward)
```css
.table {
  width: 100%;
  border-collapse: separate;
  border-spacing: 0;
}

.table thead th {
  text-align: left;
  padding: var(--space-3) var(--space-4);
  font-size: var(--text-xs);
  font-weight: var(--font-semibold);
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--text-tertiary);
  border-bottom: 1px solid var(--border-default);
}

.table tbody td {
  padding: var(--space-4);
  font-size: var(--text-sm);
  color: var(--text-primary);
  border-bottom: 1px solid var(--border-subtle);
}

.table tbody tr:hover {
  background: var(--gray-50);
}
```

### Buttons
```css
/* Primary button - Blue */
.btn-primary {
  background: var(--blue-600);
  color: var(--white);
  padding: 10px 20px;
  border-radius: 6px;
  font-size: var(--text-sm);
  font-weight: var(--font-semibold);
  border: none;
  cursor: pointer;
  transition: all 150ms ease;
}

.btn-primary:hover {
  background: var(--blue-500);
  transform: translateY(-1px);
  box-shadow: 0 4px 12px rgba(37, 99, 235, 0.2);
}

/* Secondary button - Outlined */
.btn-secondary {
  background: var(--white);
  color: var(--text-primary);
  padding: 10px 20px;
  border-radius: 6px;
  font-size: var(--text-sm);
  font-weight: var(--font-semibold);
  border: 1px solid var(--border-default);
  cursor: pointer;
  transition: all 150ms ease;
}

.btn-secondary:hover {
  border-color: var(--border-emphasis);
  background: var(--gray-50);
}

/* Text button - Minimal */
.btn-text {
  background: transparent;
  color: var(--blue-600);
  padding: 8px 12px;
  font-size: var(--text-sm);
  font-weight: var(--font-medium);
  border: none;
  cursor: pointer;
  transition: color 150ms ease;
}

.btn-text:hover {
  color: var(--blue-500);
  text-decoration: underline;
}
```

### Badges
```css
.badge {
  display: inline-flex;
  align-items: center;
  padding: 2px 8px;
  border-radius: 4px;
  font-size: var(--text-xs);
  font-weight: var(--font-medium);
  background: var(--gray-100);
  color: var(--text-secondary);
}

.badge-blue {
  background: var(--blue-50);
  color: var(--blue-600);
}

.badge-success {
  background: var(--success-bg);
  color: var(--success);
}
```

### Input Fields
```css
.input {
  width: 100%;
  padding: 10px 12px;
  font-size: var(--text-sm);
  color: var(--text-primary);
  background: var(--white);
  border: 1px solid var(--border-default);
  border-radius: 6px;
  transition: all 150ms ease;
}

.input:focus {
  outline: none;
  border-color: var(--blue-500);
  box-shadow: 0 0 0 3px var(--blue-50);
}

.input::placeholder {
  color: var(--text-tertiary);
}
```

---

## Animation Patterns

### Timing Functions
```css
--ease-in-out: cubic-bezier(0.4, 0, 0.2, 1);
--duration-fast: 150ms;
--duration-normal: 300ms;
--duration-slow: 500ms;
```

### Hover States
```css
/* Card hover - subtle lift */
.card-interactive {
  transition: all var(--duration-fast) var(--ease-in-out);
}

.card-interactive:hover {
  transform: translateY(-2px);
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.08);
}

/* Link underline animation */
.link {
  position: relative;
  color: var(--blue-600);
  text-decoration: none;
}

.link::after {
  content: '';
  position: absolute;
  bottom: -2px;
  left: 0;
  width: 0;
  height: 2px;
  background: var(--blue-600);
  transition: width var(--duration-fast);
}

.link:hover::after {
  width: 100%;
}
```

### Multi-Touch Attribution Flow Animation

This is a key differentiator showing how multiple marketing touchpoints flow into mbuzz for unified attribution.

```html
<div class="attribution-flow">
  <!-- Channel sources (left) -->
  <div class="channels">
    <div class="channel" data-channel="google">
      <div class="channel-icon" style="background: var(--channel-google)">G</div>
      <span class="channel-name">Google Ads</span>
      <div class="flow-line" data-delay="0"></div>
    </div>

    <div class="channel" data-channel="facebook">
      <div class="channel-icon" style="background: var(--channel-facebook)">f</div>
      <span class="channel-name">Facebook</span>
      <div class="flow-line" data-delay="200"></div>
    </div>

    <div class="channel" data-channel="linkedin">
      <div class="channel-icon" style="background: var(--channel-linkedin)">in</div>
      <span class="channel-name">LinkedIn</span>
      <div class="flow-line" data-delay="400"></div>
    </div>

    <div class="channel" data-channel="email">
      <div class="channel-icon" style="background: var(--channel-email)">@</div>
      <span class="channel-name">Email</span>
      <div class="flow-line" data-delay="600"></div>
    </div>

    <div class="channel" data-channel="direct">
      <div class="channel-icon" style="background: var(--channel-direct)">↗</div>
      <span class="channel-name">Direct</span>
      <div class="flow-line" data-delay="800"></div>
    </div>
  </div>

  <!-- Center hub -->
  <div class="hub">
    <div class="hub-circle">
      <svg width="60" height="60" viewBox="0 0 60 60">
        <!-- Multibuzz logo icon -->
        <circle cx="30" cy="30" r="28" fill="var(--blue-600)" />
      </svg>
    </div>
    <h3 class="hub-title">Multibuzz</h3>
    <p class="hub-subtitle">Unified Attribution</p>
  </div>

  <!-- Outputs (right) -->
  <div class="outputs">
    <div class="output">
      <div class="metric">87%</div>
      <div class="metric-label">Attribution Accuracy</div>
    </div>
  </div>
</div>

<style>
/* Flow line animation */
.flow-line {
  width: 100px;
  height: 2px;
  background: linear-gradient(
    90deg,
    transparent 0%,
    var(--blue-500) 50%,
    transparent 100%
  );
  background-size: 200% 100%;
  animation: flow 2s ease-in-out infinite;
  animation-delay: calc(var(--delay) * 1ms);
}

@keyframes flow {
  0% {
    background-position: -100% 0;
    opacity: 0.3;
  }
  50% {
    opacity: 1;
  }
  100% {
    background-position: 100% 0;
    opacity: 0.3;
  }
}

/* Hub pulse */
.hub-circle {
  animation: pulse 3s ease-in-out infinite;
}

@keyframes pulse {
  0%, 100% {
    transform: scale(1);
    opacity: 1;
  }
  50% {
    transform: scale(1.05);
    opacity: 0.9;
  }
}
</style>
```

---

## Data Visualization

### Metrics Display
```css
/* Large metric numbers */
.metric {
  font-size: var(--text-5xl);
  font-weight: var(--font-bold);
  line-height: 1;
  color: var(--text-primary);
}

.metric-label {
  font-size: var(--text-sm);
  color: var(--text-tertiary);
  margin-top: var(--space-2);
}

/* Metric card */
.metric-card {
  background: var(--white);
  border: 1px solid var(--border-default);
  border-radius: 8px;
  padding: var(--space-6);
}

.metric-card .metric {
  color: var(--blue-600);
}
```

### Status Indicators
```css
.status-indicator {
  display: inline-flex;
  align-items: center;
  gap: var(--space-2);
  font-size: var(--text-sm);
}

.status-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: var(--success);
}

.status-dot.warning {
  background: var(--warning);
}

.status-dot.error {
  background: var(--error);
}
```

---

## Page Patterns

### Hero Section
```css
.hero {
  padding: var(--space-24) 0;
  text-align: center;
  background: var(--white);
}

.hero-title {
  font-size: var(--text-6xl);
  font-weight: var(--font-bold);
  color: var(--text-primary);
  margin-bottom: var(--space-4);
}

.hero-subtitle {
  font-size: var(--text-xl);
  color: var(--text-secondary);
  max-width: 600px;
  margin: 0 auto var(--space-8);
}

.hero-cta {
  display: flex;
  gap: var(--space-4);
  justify-content: center;
}
```

### Feature Grid
```css
.feature-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: var(--space-8);
  padding: var(--space-20) 0;
}

.feature-card {
  text-align: center;
}

.feature-icon {
  width: 48px;
  height: 48px;
  margin: 0 auto var(--space-4);
  background: var(--blue-50);
  border-radius: 8px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--blue-600);
}

.feature-title {
  font-size: var(--text-xl);
  font-weight: var(--font-semibold);
  margin-bottom: var(--space-2);
  color: var(--text-primary);
}

.feature-description {
  font-size: var(--text-sm);
  color: var(--text-secondary);
  line-height: 1.6;
}

@media (max-width: 768px) {
  .feature-grid {
    grid-template-columns: 1fr;
  }
}
```

---

## Distinctive Elements

### Section Dividers
```html
<div class="section-divider">
  <div class="divider-line"></div>
</div>

<style>
.section-divider {
  padding: var(--space-12) 0;
}

.divider-line {
  height: 1px;
  background: var(--border-subtle);
}
</style>
```

### Subtle Shadows
```css
/* Minimal shadow for depth */
--shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.05);
--shadow-md: 0 4px 6px rgba(0, 0, 0, 0.05), 0 1px 3px rgba(0, 0, 0, 0.1);
--shadow-lg: 0 10px 15px rgba(0, 0, 0, 0.05), 0 4px 6px rgba(0, 0, 0, 0.1);
```

---

## Implementation Notes

### Performance
- Use CSS transforms for animations (GPU-accelerated)
- Lazy-load images and heavy content below the fold
- Minimize JavaScript for interactions where possible

### Accessibility
- Maintain WCAG AA contrast ratios (4.5:1 for body text, 3:1 for large text)
- Provide clear focus states for all interactive elements
- Support reduced-motion preferences:
  ```css
  @media (prefers-reduced-motion: reduce) {
    * {
      animation-duration: 0.01ms !important;
      animation-iteration-count: 1 !important;
      transition-duration: 0.01ms !important;
    }
  }
  ```

### Responsive Design
- Mobile-first approach
- Breakpoints: 640px (sm), 768px (md), 1024px (lg), 1280px (xl)
- Touch targets minimum 44x44px on mobile

---

## References

- **Inspiration**: [Attio](https://attio.com/) - Clean, data-forward CRM interface
- **Fonts**: Inter (Google Fonts)
- **Icons**: Heroicons or Lucide (SVG-based)
- **Colors**: Tailwind CSS default palette as foundation
