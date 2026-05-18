# Reattribution Pipeline

How mbuzz recomputes attribution credits when a conversion's journey changes
after the fact. Build history: `lib/specs/old/reattribution_reliability_spec.md`.
Incident that drove the design: `lib/specs/incidents/2026-05-18-reattribution-worker-lockup.md`.

## When it runs

Initial attribution happens once per conversion, enqueued by the `Conversion`
create callback (`Conversions::AttributionCalculationJob`).

Reattribution recomputes existing conversions' credits when something changes
their journey retroactively:

- **Identity merge** (`Identities::IdentificationService`): a visitor is linked
  to a known user, so earlier cross-device sessions now belong to that person.
- **Billing unlock** (`Billing::UnlockEventsService`): previously-locked events
  become visible.

## Flow

```
Conversions::Reattribution.enqueue(account:, conversion_ids:, trigger:)
  coalesces into an unfinished ReattributionBatch that already covers the same
  conversions, otherwise creates a ReattributionBatch and enqueues:
    Conversions::ReattributionCoordinatorJob            queue: reattribution
      ReattributionCoordinator atomically claims the batch and slices
      conversion_ids into CHUNK_SIZE (100) chunks:
        Conversions::ReattributionChunkJob (one per chunk)   queue: reattribution
          ChunkReattribution processes each conversion within a wall-clock
          budget, re-enqueuing any remainder:
            Conversions::ReattributionService recomputes one conversion's
            credits (delete_all then recalculate, idempotent)
          ReattributionBatch counters advance; the last chunk completes it
```

## Reliability properties

- **Isolated.** Reattribution runs on a dedicated `reattribution` queue and
  worker (`config/queue.yml`). The default worker never polls it, so a slow
  reattribution cannot starve latency-sensitive jobs.
- **Bounded.** 100-conversion chunks; a per-chunk wall-clock budget that
  re-enqueues the remainder; a SQL statement timeout; `limits_concurrency` of
  one chunk per batch.
- **Observable.** Every run is a `ReattributionBatch` row carrying
  total / processed / failed / status. `Infrastructure::QueueDepthAlert` flags
  any job claimed longer than its threshold.
- **Idempotent.** A finished batch is never reprocessed (coordinator claim plus
  a chunk completed-guard); recomputing a conversion yields identical credits.

## Cost

The expensive work is the attribution algorithms over the account's historical
paths: `shapley_value` is `O(2^channels)` per path. `Attribution::Markov::ConversionPathsQuery`
bounds it by caching the path set per account (short TTL) and capping it at
`MAX_PATHS`. `ShapleyValue` memoises `coalition_value`, so each distinct channel
coalition is computed once.

Future optimisation: the algorithms' channel-level output depends only on the
account's path history, not the individual conversion, so it could be computed
once per batch rather than per conversion.
