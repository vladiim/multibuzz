# Export Downloads — Cross-Host Storage Fix

**Date:** 2026-05-12
**Status:** Resolved (Active Storage + DO Spaces shipped)
**Severity:** P1 (every CSV export download returned 500)

---

## What Happened

After `427f8d2 feat(export): spend CSV export end-to-end`, every request to `/dashboard/exports/<id>/download` returned 500. Kamal logs showed the error landing 52ms after the request started, with a SolidErrors occurrence enqueued immediately before — no DB churn, an exception from the file send.

## Root Cause

The web and jobs containers run on **different hosts**:

```
web:  68.183.173.51
jobs: 159.89.136.202
```

`Dashboard::ExportJob` wrote the CSV to `tmp/exports/<prefix>.csv` on the **jobs** host's local filesystem. `Dashboard::ExportsController#download` then called `send_file export.file_path` on the **web** host. The path did not exist on the web host, so `send_file` raised before sending bytes.

This was an architectural mistake from the original feature: local-disk storage assumed a single host. We deliberately split web and jobs in the 2026-04-22 puma-jam incident, and that split made local disk untenable as a handoff substrate.

## Fix

Move export payloads to **DigitalOcean Spaces** via Active Storage. Web and jobs both write to / read from the same S3-compatible bucket.

### Storage layout

Blob keys are namespaced under the account's prefix id:

```
accounts/<account.prefix_id>/exports/<export.prefix_id>.csv
```

Bucket: `mbuzz` (reused — existing bucket already holds public `brand-assets/*`). Exports upload with private ACL; downloads are served via 5-minute signed URLs with `response-content-disposition: attachment`, so the bytes flow client ↔ Spaces and never traverse our web container.

### Download path

`Dashboard::ExportsController#download`:

```ruby
return head :gone if export.expired?
return head :gone unless export.csv.attached?
redirect_to export.download_url, allow_other_host: true
```

`Export#download_url` returns the signed Spaces URL, expiring in 5 minutes, with content-disposition set to attachment and a clean filename.

### Job path

`Dashboard::ExportJob` writes the CSV to a `Tempfile` (the same `write_to(file_path)` interface used by the three CSV services — `CsvExportService`, `FunnelCsvExportService`, `SpendCsvExportService`), then attaches the file to the Export's blob with an explicit key:

```ruby
Tempfile.create([ export.prefix_id, ".csv" ]) do |tempfile|
  tempfile.close
  export_service.write_to(tempfile.path)
  File.open(tempfile.path, "rb") { |io| attach_csv(io) }
end
```

The local tempfile is unlinked when the block exits; the canonical copy lives in Spaces.

### Auxiliary changes

- `ApplicationController` includes `ActiveStorage::SetCurrent` so blob URLs know the request host.
- `config/storage.yml` adds a `digitalocean` S3 service backed by the existing `do_spaces` credentials, and namespaces the test `Disk` root by `Process.pid` to keep parallel test workers isolated. `parallelize_teardown` wipes the per-worker root.
- `db/schema.rb` regenerated with Active Storage tables; TimescaleDB hypertable / continuous aggregate dump artifacts stripped per the CLAUDE.md guard.
- `Export#cleanup!` purges the attachment instead of `File.delete`.

## Deferred

- Drop the now-unused `exports.file_path` column in a follow-up migration once the deploy is verified (one destructive prod op at a time).
- Rotate the `do_spaces` access key — it was read into a Claude conversation transcript during the fix session.

## Why Spaces over storing CSV bytes in PostgreSQL

Considered storing the CSV as a `bytea` or `text` column on `exports`. Rejected: dashboard exports can run to many MB on accounts with months of attribution credits, and bloating a row's TOAST storage to serve a one-shot download is the wrong tradeoff. Spaces gives us cheap object storage, signed URLs, and offloads bytes from the web container entirely.
