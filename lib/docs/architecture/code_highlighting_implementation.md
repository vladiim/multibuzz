# Code Highlighting Implementation

**Status**: Complete
**Stack**: Rouge + Tailwind CSS + Stimulus (Toggle Controller)

---

## Architecture

### 1. Syntax Highlighting (Rouge)

**Gem**: `rouge` (v4.6.1)
**CSS**: Inline in `app/assets/stylesheets/application.tailwind.css` (@layer components)
**Theme**: GitHub Dark with Tailwind colors

Code blocks automatically get:
- Syntax highlighting for 200+ languages
- Dark theme (slate-900 background)
- Proper token colors (keywords pink, strings emerald, etc.)
- Language label header
- Responsive overflow scrolling

### 2. Tabbed Interface (Stimulus Toggle Controller)

**Controller**: `app/javascript/controllers/toggle_controller.js`
**Pattern**: Generic toggle/switch controller (works for any tabbed content)

Features:
- Switch between multiple code examples (Ruby, Python, PHP, cURL, etc.)
- localStorage persistence (`mbuzz_docs_language`)
- Customizable active/inactive CSS classes
- Works with `data-` attributes (no hardcoded logic)

### 3. Helper Methods

**File**: `app/helpers/docs_helper.rb`

Methods:
1. `render_markdown(text)` - Renders markdown with syntax highlighting
2. `code_tabs(examples, default:)` - Renders multi-language code tabs

---

## Usage Examples

### Single Code Block (Markdown)

````markdown
```ruby
def hello
  puts "Hello from Multibuzz!"
end
```
````

Renders: Syntax-highlighted Ruby code with dark theme

### Multi-Language Tabs (Helper)

```erb
<%= code_tabs({
  ruby: {
    label: 'Ruby',
    code: 'puts "Hello"',
    syntax: 'ruby'
  },
  python: {
    label: 'Python',
    code: 'print("Hello")',
    syntax: 'python'
  },
  curl: {
    label: 'cURL',
    code: 'curl https://api.multibuzz.com',
    syntax: 'bash'
  }
}) %>
```

Renders: Tabbed interface with tab buttons, active tab highlighting, content switching, and localStorage persistence.

---

## File Structure

```
app/
├── assets/stylesheets/
│   └── application.tailwind.css        # Code highlighting CSS (@layer components)
│
├── helpers/
│   └── docs_helper.rb                  # render_markdown + code_tabs
│
├── javascript/controllers/
│   └── toggle_controller.js            # Generic tab switching
│
└── views/docs/shared/
    └── _code_tabs.html.erb             # Code tabs partial
```

---

## How It Works

### 1. Markdown → HTML (Rouge)

```ruby
# In docs_helper.rb
class SyntaxHighlightRenderer < Redcarpet::Render::HTML
  def block_code(code, language)
    lexer = Rouge::Lexer.find_fancy(language, code)
    formatter = Rouge::Formatters::HTML.new
    highlighted_code = formatter.format(lexer.lex(code))

    # Returns HTML with .highlight and token classes
  end
end
```

Output:
```html
<div class="code-block">
  <div class="code-header">ruby</div>
  <div class="code-content">
    <pre><code>
      <span class="k">def</span>  <!-- keyword -->
      <span class="nf">hello</span>  <!-- function name -->
    </code></pre>
  </div>
</div>
```

### 2. CSS Styling (Tailwind)

```css
/* In application.tailwind.css */
@layer components {
  .highlight .k { @apply text-pink-400 font-semibold; }  /* keywords */
  .highlight .nf { @apply text-blue-400 font-semibold; } /* functions */
  .highlight .s { @apply text-emerald-300; }  /* strings */
}
```

### 3. Tab Switching (Stimulus)

```html
<div data-controller="toggle"
     data-toggle-default-value="ruby"
     data-toggle-persist-value="mbuzz_docs_language">

  <!-- Triggers -->
  <button data-toggle-target="trigger"
          data-action="click->toggle#switch"
          data-value="ruby">Ruby</button>

  <!-- Content -->
  <div data-toggle-target="content" data-value="ruby">
    <!-- Ruby code -->
  </div>
</div>
```

Stimulus controller:
1. On load: Reads `localStorage.getItem('mbuzz_docs_language')` or uses default
2. On click: Switches active tab, hides/shows content, saves preference
3. On subsequent page loads: Remembers user's language choice

---

## Extensibility

### The Toggle Controller is Generic

Works for:
- Code tabs (Ruby | Python | PHP)
- Framework toggles (Rails | Sinatra | Hanami)
- Feature comparisons (Free | Pro | Enterprise)
- Any content that needs tab switching

Example - Framework Selector:
```html
<div data-controller="toggle" data-toggle-default-value="rails">
  <button data-toggle-target="trigger" data-value="rails">Rails</button>
  <button data-toggle-target="trigger" data-value="sinatra">Sinatra</button>

  <div data-toggle-target="content" data-value="rails">
    Rails-specific docs
  </div>
  <div data-toggle-target="content" data-value="sinatra">
    Sinatra-specific docs
  </div>
</div>
```

### Add New Languages

Just add to the `code_tabs` call:

```erb
<%= code_tabs({
  ruby: { label: 'Ruby', code: '...', syntax: 'ruby' },
  python: { label: 'Python', code: '...', syntax: 'python' },
  php: { label: 'PHP', code: '...', syntax: 'php' },
  go: { label: 'Go', code: '...', syntax: 'go' },
  rust: { label: 'Rust', code: '...', syntax: 'rust' }
}) %>
```

No code changes needed - the toggle controller handles any number of tabs.

---

## Supported Languages

Rouge supports 200+ languages:

**Programming**: Ruby, Python, PHP, JavaScript, TypeScript, Go, Rust, Java, C, C++, C#, Swift, Kotlin, Scala, Elixir

**Web**: HTML, CSS, SCSS, LESS, JSX, Vue, Svelte

**Shell**: Bash, Zsh, PowerShell

**Data**: JSON, YAML, TOML, XML

**Query**: SQL, GraphQL

**Config**: Dockerfile, Nginx, Apache

---

## Color Palette

**Background**:
- Code block: `slate-900` (#0f172a)
- Header: `slate-800` (#1e293b)

**Syntax**:
- Keywords: `pink-400` (#f472b6) - bold
- Functions: `blue-400` (#60a5fa) - bold
- Strings: `emerald-300` (#6ee7b7)
- Numbers: `orange-400` (#fb923c)
- Comments: `slate-500` (#64748b) - italic
- Variables: `blue-300` (#93c5fd)
- Classes: `yellow-400` (#facc15) - bold

**Tabs**:
- Active: `slate-900` bg + `blue-400` text
- Inactive: `slate-400` text + hover `slate-200`

---

## Debugging

### CSS not applying?

```bash
bin/rails tailwindcss:build
```

### Tabs not switching?

Check browser console for JavaScript errors. Ensure Stimulus is loaded:

```bash
grep "stimulus" app/javascript/controllers/application.js
```

### Wrong colors?

Verify tailwind config includes all color classes:

```bash
cat tailwind.config.js
```

Should have all slate, blue, pink, emerald, orange colors enabled.

---

## Performance

**Server-side rendering**:
- Rouge processes code once (server-side)
- Browser receives static HTML
- No client-side syntax highlighting libraries
- No runtime performance cost

**Bundle size**:
- Toggle controller: ~3KB
- CSS: ~5KB (compressed)
- Total JS: < 10KB
