# Multibuzz Design System & Style Guide

## Brand Identity

### Positioning
**"Multi-Channel Marketing Attribution - No Frills, All Data"**
- Developer-focused analytics platform
- Multi-channel = Multi-color (visual metaphor)
- Professional but vibrant
- Data-driven, not marketing-driven

### Tone
- Direct and technical
- Confident and modern
- Professional without being boring
- Energetic without being chaotic

---

## Color System

### Philosophy
**Multi-colored by design** - Each vibrant color represents a marketing channel or data category. This isn't decoration; it's functional design that makes complex attribution data immediately scannable.

### Base Palette (Foundation)

**Neutrals - Slate Scale**
```css
/* Dark Mode Base (optional Phase 2) */
--slate-900: #0F172A;  /* Primary dark background */
--slate-800: #1E293B;  /* Secondary dark background */
--slate-700: #334155;  /* Tertiary dark */

/* Mid-tones */
--slate-600: #475569;  /* Secondary text */
--slate-500: #64748B;  /* Disabled text */
--slate-400: #94A3B8;  /* Muted text, placeholders */
--slate-300: #CBD5E1;  /* Borders */
--slate-200: #E2E8F0;  /* Dividers */

/* Light Mode Base (primary) */
--slate-100: #F1F5F9;  /* Subtle backgrounds */
--slate-50:  #F8FAFC;  /* Page background */
--white:     #FFFFFF;  /* Cards, surfaces */

/* Text Colors */
--text-primary:   #0F172A;  /* Headings, primary content */
--text-secondary: #475569;  /* Body text */
--text-muted:     #94A3B8;  /* Labels, metadata */
```

**Usage:**
- Page backgrounds: `slate-50` (#F8FAFC)
- Cards/surfaces: `white` (#FFFFFF)
- Primary text: `slate-900` (#0F172A)
- Secondary text: `slate-600` (#475569)
- Borders/dividers: `slate-200` (#E2E8F0)

---

### Vibrant Accent Palette

**Primary Accent - Electric Blue**
```css
--blue-600: #2563EB;  /* Primary CTA hover */
--blue-500: #3B82F6;  /* Primary CTA, links (DEFAULT) */
--blue-400: #60A5FA;  /* Hover states */
--blue-50:  #EFF6FF;  /* Light backgrounds */
```
**Use for:** Primary buttons, links, main CTAs, Google/Search channel

**Secondary Accents - Channel Colors**
```css
/* Purple - Social Media */
--purple-600: #9333EA;
--purple-500: #A855F7;  /* Facebook, Instagram, Social */
--purple-400: #C084FC;
--purple-50:  #FAF5FF;

/* Pink - Paid Advertising */
--pink-600: #DB2777;
--pink-500: #EC4899;    /* Paid ads, sponsored content */
--pink-400: #F472B6;
--pink-50:  #FDF2F8;

/* Orange - Referral Traffic */
--orange-600: #EA580C;
--orange-500: #F97316;  /* Referral, partner traffic */
--orange-400: #FB923C;
--orange-50:  #FFF7ED;

/* Emerald - Email & Organic */
--emerald-600: #059669;
--emerald-500: #10B981; /* Email campaigns, organic */
--emerald-400: #34D399;
--emerald-50:  #ECFDF5;

/* Yellow - Direct Traffic */
--yellow-500: #EAB308;  /* Direct traffic, bookmarks */
--yellow-400: #FACC15;
--yellow-50:  #FEFCE8;
```

**Semantic Colors**
```css
/* Success */
--success: #10B981;     /* emerald-500 */
--success-bg: #ECFDF5;  /* emerald-50 */

/* Warning */
--warning: #F59E0B;     /* amber-500 */
--warning-bg: #FFFBEB;  /* amber-50 */

/* Error */
--error: #EF4444;       /* red-500 */
--error-bg: #FEF2F2;    /* red-50 */

/* Info */
--info: #3B82F6;        /* blue-500 */
--info-bg: #EFF6FF;     /* blue-50 */
```

---

### Color Usage Guidelines

#### The 80/20 Rule
**80% Neutral (slate), 20% Vibrant**
- Neutrals create professional foundation
- Vibrant colors highlight data and actions
- Don't overwhelm - vibrant should feel intentional

#### Channel Color Mapping (UTM Sources)
```
Google / Search:     #3B82F6  (blue-500)
Facebook / Social:   #A855F7  (purple-500)
Email Campaigns:     #10B981  (emerald-500)
Paid Advertising:    #EC4899  (pink-500)
Referral Traffic:    #F97316  (orange-500)
Direct / Bookmarks:  #FACC15  (yellow-500)
Other / Unknown:     #64748B  (slate-500)
```

#### Button Colors
```
Primary CTA:         bg-blue-500 hover:bg-blue-600
Secondary:           bg-white border-slate-300 hover:bg-slate-50
Destructive:         bg-red-500 hover:bg-red-600
Success:             bg-emerald-500 hover:bg-emerald-600
```

#### Chart Colors (Data Visualization)
Use the vibrant palette in order:
1. Blue (#3B82F6) - Primary metric
2. Purple (#A855F7) - Secondary
3. Emerald (#10B981) - Third
4. Orange (#F97316) - Fourth
5. Pink (#EC4899) - Fifth
6. Yellow (#FACC15) - Use sparingly

#### Accessibility Requirements
- **Minimum contrast:** 4.5:1 for body text (WCAG AA)
- **Minimum contrast:** 3:1 for large text (18px+)
- All vibrant colors on white backgrounds pass WCAG AA
- Never use yellow-500 for text (use yellow-600+ for contrast)
- Test color combinations: https://webaim.org/resources/contrastchecker/

---

## Typography

### Font Families
```css
/* Sans-serif (Primary UI Font) */
font-family: -apple-system, BlinkMacSystemFont, "Segoe UI",
             Roboto, "Helvetica Neue", Arial, sans-serif;

/* Monospace (Code, Data, IDs) */
font-family: ui-monospace, SFMono-Regular, "SF Mono",
             Menlo, Consolas, "Liberation Mono", monospace;
```

### Type Scale (Tailwind Classes)
```
text-xs:     12px / 16px  - Micro labels, badges, timestamps
text-sm:     14px / 20px  - Table data, secondary text, captions
text-base:   16px / 24px  - Body text (DEFAULT)
text-lg:     18px / 28px  - Emphasized body text
text-xl:     20px / 28px  - Section headings, large labels
text-2xl:    24px / 32px  - Card titles, subsections
text-3xl:    30px / 36px  - Page titles
text-4xl:    36px / 40px  - Hero secondary headings
text-5xl:    48px / 1     - Hero primary headings
text-6xl:    60px / 1     - Homepage hero only
```

### Font Weights
```
font-normal:    400  - Body text, paragraphs
font-medium:    500  - Table headers, labels, navigation
font-semibold:  600  - Stat values, emphasis, button text
font-bold:      700  - Headings, logo, strong emphasis
font-extrabold: 800  - Hero headings only
```

### Common Text Styles
```html
<!-- Body text -->
<p class="text-base text-slate-600">

<!-- Page heading -->
<h1 class="text-3xl font-bold text-slate-900">

<!-- Section heading -->
<h2 class="text-2xl font-semibold text-slate-900">

<!-- Label -->
<label class="text-sm font-medium text-slate-700">

<!-- Small caps label (table headers) -->
<th class="text-xs font-medium text-slate-500 uppercase tracking-wider">

<!-- Stat value -->
<dd class="text-3xl font-semibold text-slate-900">

<!-- Muted text -->
<span class="text-sm text-slate-500">

<!-- Timestamp -->
<time class="text-xs text-slate-400">
```

### Line Height & Spacing
```
Headings:    leading-tight (1.25)
Body text:   leading-normal (1.5)
Labels:      leading-snug (1.375)

Max line length:  max-w-3xl (768px) for readable text
Paragraph spacing: space-y-4 (16px between paragraphs)
```

---

## Spacing System

### Container Widths
```
max-w-7xl:  1280px  - Dashboard, data-heavy pages (DEFAULT)
max-w-5xl:  1024px  - Content pages, documentation
max-w-3xl:  768px   - Articles, long-form text
max-w-2xl:  672px   - Narrow content
max-w-md:   448px   - Login forms, small modals
```

### Padding & Margin Scale
```
space-1:   4px    - Tiny gaps
space-2:   8px    - Tight spacing (badges)
space-3:   12px   - Compact
space-4:   16px   - Standard (buttons, inputs)
space-5:   20px   - Comfortable
space-6:   24px   - Spacious (cards)
space-8:   32px   - Large gaps (sections)
space-10:  40px   - Very large (major sections)
space-12:  48px   - Extra large
space-16:  64px   - Hero sections
```

### Component Spacing
```
Between stat cards:       gap-5 (20px)
Between table rows:       divide-y (1px)
Between sections:         mt-8 (32px)
Between major blocks:     mt-12 (48px)
Page padding:             py-10 (40px top/bottom)
Container side padding:   px-4 sm:px-6 lg:px-8
```

---

## Components

### Navigation Bar
```html
<nav class="bg-white shadow-sm border-b border-slate-200">
  <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
    <div class="flex justify-between h-16">
      <div class="flex items-center">
        <h1 class="text-xl font-bold text-slate-900">
          Multi<span class="text-blue-500">buzz</span>
        </h1>
      </div>
      <div class="flex items-center space-x-4">
        <a href="#" class="text-slate-600 hover:text-slate-900">Link</a>
      </div>
    </div>
  </div>
</nav>
```

**Specs:**
- Height: 64px (h-16)
- Background: white
- Border: slate-200 bottom border
- Logo: "Multi" (slate-900) + "buzz" (blue-500)
- Links: slate-600, hover to slate-900

---

### Buttons

**Primary (CTA)**
```html
<button class="inline-flex items-center px-4 py-2 border border-transparent
               text-base font-semibold rounded-md text-white
               bg-blue-500 hover:bg-blue-600
               focus:outline-none focus:ring-2 focus:ring-offset-2
               focus:ring-blue-500 transition-colors duration-150">
  Primary Action
</button>
```

**Secondary**
```html
<button class="inline-flex items-center px-4 py-2 border border-slate-300
               text-base font-semibold rounded-md text-slate-700
               bg-white hover:bg-slate-50
               focus:outline-none focus:ring-2 focus:ring-offset-2
               focus:ring-blue-500 transition-colors duration-150">
  Secondary Action
</button>
```

**Text Button**
```html
<button class="text-slate-600 hover:text-slate-900 font-medium
               transition-colors duration-150">
  Text Action
</button>
```

**Destructive**
```html
<button class="inline-flex items-center px-4 py-2 border border-transparent
               text-base font-semibold rounded-md text-white
               bg-red-500 hover:bg-red-600
               focus:outline-none focus:ring-2 focus:ring-offset-2
               focus:ring-red-500 transition-colors duration-150">
  Delete
</button>
```

**Button Sizes:**
```
Small:   px-3 py-1.5 text-sm
Medium:  px-4 py-2 text-base (DEFAULT)
Large:   px-6 py-3 text-lg
```

---

### Cards

**Stat Card**
```html
<div class="bg-white overflow-hidden shadow-sm rounded-lg border border-slate-200">
  <div class="px-4 py-5 sm:p-6">
    <dt class="text-sm font-medium text-slate-500 truncate">
      Total Events
    </dt>
    <dd class="mt-1 text-3xl font-semibold text-slate-900">
      1,234,567
    </dd>
  </div>
</div>
```

**Stat Card with Color Accent**
```html
<div class="bg-white overflow-hidden shadow-sm rounded-lg border-l-4 border-blue-500">
  <div class="px-4 py-5 sm:p-6">
    <dt class="text-sm font-medium text-slate-500">Google Traffic</dt>
    <dd class="mt-1 text-3xl font-semibold text-slate-900">45,231</dd>
    <p class="mt-2 text-sm text-emerald-600">↑ 12% from last week</p>
  </div>
</div>
```

**Content Card**
```html
<div class="bg-white shadow-sm overflow-hidden rounded-lg border border-slate-200">
  <div class="px-4 py-5 sm:px-6 border-b border-slate-200">
    <h3 class="text-lg font-semibold text-slate-900">Card Title</h3>
    <p class="mt-1 text-sm text-slate-500">Optional description</p>
  </div>
  <div class="px-4 py-5 sm:p-6">
    <!-- Card content -->
  </div>
</div>
```

---

### Tables

```html
<div class="overflow-x-auto">
  <table class="min-w-full divide-y divide-slate-200">
    <thead class="bg-slate-50">
      <tr>
        <th class="px-6 py-3 text-left text-xs font-medium text-slate-500
                   uppercase tracking-wider">
          Header
        </th>
      </tr>
    </thead>
    <tbody class="bg-white divide-y divide-slate-200">
      <tr class="hover:bg-slate-50 transition-colors duration-150">
        <td class="px-6 py-4 whitespace-nowrap text-sm text-slate-900">
          Data
        </td>
      </tr>
    </tbody>
  </table>
</div>
```

**Table with Channel Colors:**
```html
<tr>
  <td class="px-6 py-4 whitespace-nowrap">
    <span class="inline-flex items-center">
      <span class="w-2 h-2 rounded-full bg-blue-500 mr-2"></span>
      <span class="text-sm text-slate-900">Google</span>
    </span>
  </td>
  <td class="px-6 py-4 text-sm font-semibold text-slate-900">
    12,345
  </td>
</tr>
```

---

### Forms

**Input Field**
```html
<div>
  <label for="email" class="block text-sm font-medium text-slate-700">
    Email address
  </label>
  <input type="email" id="email"
         class="mt-1 block w-full px-3 py-2
                border border-slate-300 rounded-md shadow-sm
                text-slate-900 placeholder-slate-400
                focus:outline-none focus:ring-2 focus:ring-blue-500
                focus:border-blue-500
                sm:text-sm transition-colors duration-150"
         placeholder="you@example.com" />
</div>
```

**Error State**
```html
<input class="border-red-300 text-red-900 placeholder-red-300
              focus:ring-red-500 focus:border-red-500" />
<p class="mt-2 text-sm text-red-600">Error message here</p>
```

**Success State**
```html
<input class="border-emerald-300 text-slate-900
              focus:ring-emerald-500 focus:border-emerald-500" />
<p class="mt-2 text-sm text-emerald-600">Looks good!</p>
```

---

### Badges & Pills

**Status Badge**
```html
<!-- Success -->
<span class="inline-flex items-center px-2.5 py-0.5 rounded-full
             text-xs font-medium bg-emerald-50 text-emerald-700
             border border-emerald-200">
  Active
</span>

<!-- Warning -->
<span class="inline-flex items-center px-2.5 py-0.5 rounded-full
             text-xs font-medium bg-yellow-50 text-yellow-700
             border border-yellow-200">
  Pending
</span>

<!-- Error -->
<span class="inline-flex items-center px-2.5 py-0.5 rounded-full
             text-xs font-medium bg-red-50 text-red-700
             border border-red-200">
  Failed
</span>

<!-- Neutral -->
<span class="inline-flex items-center px-2.5 py-0.5 rounded-full
             text-xs font-medium bg-slate-100 text-slate-700
             border border-slate-200">
  Default
</span>
```

**Channel Badge (with color dot)**
```html
<span class="inline-flex items-center px-3 py-1 rounded-full
             text-sm font-medium bg-blue-50 text-blue-700
             border border-blue-200">
  <span class="w-2 h-2 rounded-full bg-blue-500 mr-1.5"></span>
  Google
</span>
```

---

## Layout Patterns

### Page Structure (Dashboard)
```html
<div class="min-h-screen bg-slate-50">
  <!-- Navigation (64px fixed height) -->
  <nav class="bg-white shadow-sm border-b border-slate-200">
    <!-- Nav content -->
  </nav>

  <!-- Main content area -->
  <div class="py-10">
    <!-- Page header -->
    <header>
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <h1 class="text-3xl font-bold text-slate-900">Page Title</h1>
        <p class="mt-2 text-sm text-slate-600">Optional description</p>
      </div>
    </header>

    <!-- Page content -->
    <main>
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <!-- Content here -->
      </div>
    </main>
  </div>
</div>
```

### Stats Grid
```html
<div class="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-4">
  <!-- Stat cards -->
</div>
```

### Two-Column Layout
```html
<div class="grid grid-cols-1 gap-6 lg:grid-cols-2">
  <div><!-- Left column --></div>
  <div><!-- Right column --></div>
</div>
```

### Three-Column Layout
```html
<div class="grid grid-cols-1 gap-6 md:grid-cols-2 lg:grid-cols-3">
  <div><!-- Column 1 --></div>
  <div><!-- Column 2 --></div>
  <div><!-- Column 3 --></div>
</div>
```

---

## Responsive Design

### Breakpoints (Tailwind)
```
sm:   640px   - Tablet portrait
md:   768px   - Tablet landscape
lg:   1024px  - Desktop
xl:   1280px  - Large desktop
2xl:  1536px  - Extra large desktop
```

### Mobile-First Approach
Always start with mobile styles, then add larger breakpoints:

```html
<!-- Bad -->
<div class="lg:text-base md:text-sm text-xs">

<!-- Good -->
<div class="text-xs md:text-sm lg:text-base">
```

### Common Responsive Patterns
```
Padding:        px-4 sm:px-6 lg:px-8
Grid columns:   grid-cols-1 sm:grid-cols-2 lg:grid-cols-4
Text size:      text-2xl sm:text-3xl lg:text-4xl
Hide mobile:    hidden lg:block
Show mobile:    block lg:hidden
Stack mobile:   flex-col lg:flex-row
```

### Testing Breakpoints
- **Mobile:** 375px (iPhone SE)
- **Tablet:** 768px (iPad)
- **Desktop:** 1280px (laptop)
- **Large:** 1920px (desktop monitor)

---

## Visual Effects

### Shadows
```
shadow-sm:   Subtle (cards, inputs)
shadow:      Default (elevated cards)
shadow-md:   Medium (dropdowns)
shadow-lg:   Large (modals)
shadow-xl:   Extra large (popovers)
```

**Usage:**
- Cards: `shadow-sm`
- Hover states: `hover:shadow-md`
- Modals: `shadow-xl`
- Navigation: `shadow-sm` (or just border)

### Border Radius
```
rounded-sm:  2px   - Tight (badges)
rounded:     4px   - Default (buttons, inputs)
rounded-md:  6px   - Medium (cards)
rounded-lg:  8px   - Large (hero sections)
rounded-xl:  12px  - Extra large (images)
rounded-full: ∞    - Circles (avatars, dots)
```

### Borders
```
border:          1px solid slate-200
border-2:        2px solid
border-t:        Top only
border-l-4:      4px left (card accents)
divide-y:        Between rows (tables)
```

---

## Animation & Interaction

### Transitions
```
transition-colors duration-150  - Color changes (buttons, links)
transition-all duration-200     - Multiple properties
transition-opacity duration-300 - Fade effects
```

### Hover States
```
Buttons:       hover:bg-blue-600 (darken by 100)
Links:         hover:text-slate-900
Cards:         hover:shadow-md
Table rows:    hover:bg-slate-50
```

### Focus States (Accessibility Required)
```
focus:outline-none
focus:ring-2
focus:ring-offset-2
focus:ring-blue-500
```

### Loading States
```
<!-- Skeleton loader -->
<div class="animate-pulse bg-slate-200 h-4 w-full rounded"></div>

<!-- Disabled button -->
<button disabled class="opacity-50 cursor-not-allowed">
  Disabled
</button>

<!-- Spinner -->
<svg class="animate-spin h-5 w-5 text-blue-500">...</svg>
```

---

## Accessibility Standards

### Color Contrast Requirements (WCAG AA)
- **Body text (< 18px):** 4.5:1 minimum
- **Large text (≥ 18px):** 3:1 minimum
- **UI components:** 3:1 minimum

✅ **Passing Combinations:**
- slate-900 on white: 13.6:1
- slate-600 on white: 4.6:1
- blue-500 on white: 4.5:1
- All vibrant colors on white: 4.5:1+

❌ **Failing Combinations:**
- yellow-400 on white: 1.9:1 (use yellow-500+)
- slate-400 on white: 2.8:1 (labels only)

### Focus Management
- All interactive elements must show focus indicator
- Use: `focus:ring-2 focus:ring-blue-500`
- Never remove outline without replacement
- Keyboard navigation must be obvious

### Semantic HTML
```
<nav>        Navigation landmarks
<main>       Main content
<header>     Page/section headers
<footer>     Page/section footers
<article>    Independent content
<section>    Thematic grouping
<aside>      Sidebar content
```

### ARIA Labels
```html
<!-- Button with icon only -->
<button aria-label="Close">
  <svg>...</svg>
</button>

<!-- Form errors -->
<input aria-describedby="email-error" aria-invalid="true" />
<p id="email-error" role="alert">Email is required</p>
```

---

## Code Formatting

### Tailwind Class Order
1. **Layout:** `flex`, `grid`, `block`, `inline`
2. **Positioning:** `relative`, `absolute`, `top-0`
3. **Box model:** `w-full`, `h-16`, `p-4`, `m-2`
4. **Typography:** `text-base`, `font-semibold`, `text-slate-900`
5. **Visual:** `bg-white`, `border`, `shadow`, `rounded`
6. **Interactivity:** `hover:bg-blue-600`, `focus:ring-2`, `transition-colors`

### Line Breaking (for readability)
```html
<!-- Good: Break long class lists logically -->
<button class="inline-flex items-center px-4 py-2
               text-base font-semibold
               text-white bg-blue-500
               border border-transparent rounded-md shadow-sm
               hover:bg-blue-600 focus:outline-none
               focus:ring-2 focus:ring-offset-2 focus:ring-blue-500
               transition-colors duration-150">
  Click Me
</button>
```

---

## Don'ts (Anti-Patterns)

### ❌ Never Do
- Use more than 3 vibrant colors on a single page (outside charts)
- Use yellow for text (contrast issues)
- Use gradients (keep it flat)
- Use custom fonts (system fonts are fast + reliable)
- Use pure black (#000) - use slate-900 instead
- Mix warm and cool grays (stick to slate)
- Use color alone to convey meaning (add icons/text)
- Create arbitrary spacing (use Tailwind scale)
- Override focus styles without replacement
- Use non-semantic HTML (divs for everything)

### ❌ Color Mistakes
- Too many vibrant colors at once (overwhelming)
- Low contrast text (yellow-400 on white)
- Using color without additional indicators (colorblind users)
- Inconsistent channel colors (Google is always blue-500)

---

## Design Checklist

Before shipping any page/feature:

**Visual Design**
- [ ] Works at 375px (mobile) and 1280px (desktop)
- [ ] Uses system font stack (no custom fonts)
- [ ] Follows 80/20 rule (80% neutral, 20% vibrant)
- [ ] Color combinations pass WCAG AA (4.5:1)
- [ ] Consistent spacing (uses Tailwind scale)
- [ ] Clear visual hierarchy

**Interaction**
- [ ] All interactive elements have hover states
- [ ] All interactive elements have focus indicators
- [ ] Transitions are smooth (150-300ms)
- [ ] Loading states for async actions
- [ ] Error states are clear and helpful

**Accessibility**
- [ ] Keyboard navigable
- [ ] Screen reader tested
- [ ] Color contrast verified
- [ ] Semantic HTML used
- [ ] ARIA labels where needed
- [ ] Form errors properly associated

**Performance**
- [ ] No console errors
- [ ] Fast load time (< 2s)
- [ ] Images optimized
- [ ] No layout shift (CLS)

**Content**
- [ ] Clear, concise copy
- [ ] No jargon (or explained)
- [ ] Consistent terminology
- [ ] Proper grammar/spelling

---

## Inspiration & References

### Similar Aesthetics
- **PostHog** - Vibrant, developer-friendly
- **Linear** - Polish, attention to detail
- **Plausible** - Clean, minimal
- **Segment** - Professional data platform

### Tools
- **Contrast Checker:** https://webaim.org/resources/contrastchecker/
- **Tailwind UI:** https://tailwindui.com
- **Headless UI:** https://headlessui.com
- **Hero Icons:** https://heroicons.com

---

## Quick Reference

### Most Common Patterns

**Page container:**
```html
<div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
```

**Section spacing:**
```html
<div class="mt-8">
```

**Stat card:**
```html
<div class="bg-white shadow-sm rounded-lg border border-slate-200 p-6">
```

**Primary button:**
```html
<button class="px-4 py-2 text-white bg-blue-500 hover:bg-blue-600
               rounded-md font-semibold transition-colors">
```

**Channel indicator:**
```html
<span class="inline-flex items-center">
  <span class="w-2 h-2 rounded-full bg-blue-500 mr-2"></span>
  Google
</span>
```

---

**This is your source of truth. When in doubt, refer back to this guide.**
