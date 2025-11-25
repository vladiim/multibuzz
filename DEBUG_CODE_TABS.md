# Code Tabs Debug Summary

## ROOT CAUSE FOUND
Precompiled assets in `public/assets/` contained OLD versions of JavaScript controllers.
In development, Rails was serving these stale compiled files instead of the source files.

## FIXED
- Deleted `public/assets/` directory (should not exist in dev)
- Now Rails will serve files directly from source

## TO RUN THE APP CORRECTLY

**Use this command:**
```bash
bin/dev
```

This runs BOTH:
1. Rails server (`bin/rails server`)
2. Tailwind CSS watcher (`bin/rails tailwindcss:watch`)

**DO NOT use:** `bin/rails server` alone - this won't compile Tailwind CSS changes

## VERIFY IT WORKS

1. Stop any running servers
2. Run: `bin/dev`
3. Hard refresh browser: Cmd+Shift+R (Mac) or Ctrl+Shift+R (Windows)
4. Check browser console - should have NO errors
5. Click tabs - should work now

## FILE STATUS

### JavaScript Controller (CORRECT)
- Source: `app/javascript/controllers/toggle_controller.js`
- Has `select(event)` method on line 57
- Properly handles tab switching

### HTML Template (CORRECT)  
- Source: `app/views/docs/shared/_code_tabs.html.erb`
- Uses `data-action="click->toggle#select"`
- Matches controller method

### CSS Styles (CORRECT)
- Source: `app/assets/stylesheets/application.tailwind.css`
- Lines 74-91: Code tabs styles
- `.code-tab.active` has blue text + blue border
- `.code-panel.active` shows, others hidden

## EXPECTED BEHAVIOR

### Tabs:
- Ruby tab: Active by default (blue text, blue bottom border)
- REST API tab: Inactive (gray text, hover shows lighter gray)
- Clicking switches tabs smoothly
- Selection persists in localStorage

### Code:
- Syntax highlighted with Rouge
- Ruby: Pink keywords, emerald strings, blue methods
- Dark slate background
- Proper rounded corners

