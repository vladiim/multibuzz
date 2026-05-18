# Project Memory

Repo-local persistent memory for mbuzz. One fact per file. This index is read for fast context, so keep it to one line per memory.

Each memory file carries frontmatter (`name`, `description`, `metadata.type`) and a body. Types: `user`, `feedback`, `project`, `reference`. Link related memories with `[[name]]`.

Never put secrets, tokens, API keys, account IDs, email addresses, or customer PII in these files. They are committed to git. Use placeholders (see the CLAUDE.md secrets rule).

## Active Incidents / Remediation
- [2026-04-22 outage remediation](project_2026_04_22_outage_remediation.md): shipped, queues unpaused, jobs on a dedicated droplet
- [BatchReattributionJob worker lockup](project_batch_reattribution_worker_lockup.md): 2026-05-18, an unbounded job froze the 3-thread worker; fix specced in `lib/specs/reattribution_reliability_spec.md`
