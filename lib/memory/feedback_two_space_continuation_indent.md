---
name: feedback-two-space-continuation-indent
description: Line continuations and nested HTML/ERB indent by exactly two spaces. Never align across lines.
metadata:
  type: feedback
---

CLAUDE.md "Formatting" already says this, but I keep regressing on it. Two distinct rules to apply on every edit:

1. **2-space indent for line continuations.** Multi-line method calls, hash literals, ERB `<%= render ... %>` arguments — the continuation lines are indented exactly two spaces from the start of the opening line, not aligned under the first argument or the opening parenthesis.

   Wrong (the pattern I keep producing):
   ```erb
       <%= render "shared/success_state",
             emoji: "✅",
             heading: "..." %>
   ```
   Right:
   ```erb
       <%= render "shared/success_state",
         emoji: "✅",
         heading: "..." %>
   ```

   Ruby example, wrong:
   ```ruby
     account.update!(
                       setup_path: :assisted,
                       setup_profile: {}
                     )
   ```
   Right:
   ```ruby
     account.update!(
       setup_path: :assisted,
       setup_profile: {}
     )
   ```

2. **Never align to match previous content.** No padding spaces to make `=`, `=>`, `then`, or similar tokens line up across consecutive lines. Each line uses single-space token separation regardless of the next.

   Wrong:
   ```ruby
   @scheduling_form   = SchedulingPreferencesPresenter.from(...)
   @kickoff_booked    = current_account.guided_setup&.kickoff_booked_at.present?
   @kickoff_call_done = current_account.guided_setup&.kickoff_call_at.present?
   ```
   Right:
   ```ruby
   @scheduling_form = SchedulingPreferencesPresenter.from(...)
   @kickoff_booked = current_account.guided_setup&.kickoff_booked_at.present?
   @kickoff_call_done = current_account.guided_setup&.kickoff_call_at.present?
   ```

   Hash literals with aligned `=>` arrows, `when`/`then` arms aligned across cases — all violations. Strip the padding even if the surrounding code has it; the surrounding code is wrong too.

**Why:** User has corrected this multiple times across sessions. Reads as sloppy ("a million times"). Don't reproduce existing aligned code — match the rule, not the file.

**How to apply:** Before writing any multi-line construct, default to 2-space continuation. Before writing any vertical block of assignments / hash entries / case arms, default to single-space token separation. After writing, scan diff for any column-aligned token across consecutive lines — if you see it, it's a bug.

Related: [[feedback_code_style]] (no procedural code, no unnecessary local vars), CLAUDE.md "Formatting" section.
