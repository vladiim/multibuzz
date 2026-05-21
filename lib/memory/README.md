# Project Memory

Repo-local persistent memory for mbuzz. One fact per file. This index is read for fast context, so keep it to one line per memory.

Each memory file carries frontmatter (`name`, `description`, `metadata.type`) and a body. Types: `user`, `feedback`, `project`, `reference`. Link related memories with `[[name]]`.

Never put secrets, tokens, API keys, account IDs, email addresses, or customer PII in these files. They are committed to git. Use placeholders (see the CLAUDE.md secrets rule).

## Active Incidents / Remediation
- [2026-04-22 outage remediation](project_2026_04_22_outage_remediation.md): shipped, queues unpaused, jobs on a dedicated droplet
- [BatchReattributionJob worker lockup](project_batch_reattribution_worker_lockup.md): 2026-05-18, an unbounded job froze the 3-thread worker; fix specced in `lib/specs/old/reattribution_reliability_spec.md`
- [Sessions fingerprint CPU storm](project_2026_05_21_sessions_fingerprint_cpu_storm.md): 2026-05-21, missing `(account_id, device_fingerprint, created_at)` index held the per-create advisory lock for 700ms+; index shipped

## Feedback
- [Visible form inputs are non-negotiable](feedback_visible_form_inputs.md): every input/select/textarea needs a visible resting border and real padding — never transparent-at-rest
- [Register every new admin surface in `AdminTools::ALL`](feedback_admin_surfaces_register_in_admintools.md): the `/admin` hub renders this registry; an unlisted surface is invisible to operators
