# pg-r2-backup

Encrypted PostgreSQL backups to Cloudflare R2 with grandfather-father-son retention enforced by R2 lifecycle rules.

## Design

- `pg_dump` → `gzip` → `gpg` (AES256 symmetric) → upload to R2
- Writes to 1–3 prefixes per run; R2 lifecycle expires each independently:
  - `daily/` → kept 7 days
  - `weekly/` → kept 35 days (written on Sundays UTC)
  - `monthly/` → kept 400 days (written on 1st of month UTC)
- R2 API token should have **Object Write only** — no delete. R2 handles retention on its side, so a compromised backup container cannot erase history.
- Optional healthcheck ping on success (e.g. healthchecks.io) for dead-man alerting.

## Usage

```yaml
services:
  backup:
    image: ghcr.io/iemarjay/pg-r2-backup:latest
    restart: unless-stopped
    env_file:
      - .env.backup
    depends_on:
      - postgres
```

See [`.env.backup.example`](.env.backup.example) for env vars.

## Environment variables

| Var | Required | Default | Description |
|---|---|---|---|
| `PG_HOST` | ✅ | | Postgres host |
| `PG_PORT` | | `5432` | |
| `PG_USER` | ✅ | | |
| `PG_PASSWORD` | ✅ | | |
| `PG_DATABASE` | ✅ | | |
| `R2_ACCOUNT_ID` | ✅ | | Cloudflare account ID |
| `R2_BUCKET` | ✅ | | Bucket name |
| `R2_ACCESS_KEY_ID` | ✅ | | R2 API token ID (write-only) |
| `R2_SECRET_ACCESS_KEY` | ✅ | | R2 API token secret |
| `ENCRYPTION_PASSPHRASE` | ✅ | | gpg symmetric passphrase. Store separately from R2 creds. If lost, backups are unrecoverable. |
| `BACKUP_CRON` | | `0 2 * * *` | Cron expression (container TZ is UTC by default) |
| `BACKUP_NAME_PREFIX` | | `backup` | Filename prefix, e.g. `panelsuite` |
| `HEALTHCHECK_URL` | | | Optional. Pinged on success (and `/start` on start). |
| `TZ` | | `UTC` | |

## R2 setup (one-time)

1. Create a bucket (e.g. `panelsuite-backups`).
2. Create an **API Token**: permissions `Object Read & Write` scoped to that bucket. (Write-only isn't surfaced in the dashboard today — use a custom token with `Object Read, Object Write` but no `Object Delete`.)
3. Add **Object Lifecycle rules** on the bucket:
   - Prefix `daily/` → expire after **7 days**
   - Prefix `weekly/` → expire after **35 days**
   - Prefix `monthly/` → expire after **400 days**
4. Optionally enable **bucket versioning** (additional defence against overwrite).

## Restore

Full restore to a target Postgres (which the container can reach):

```bash
docker run --rm -it --env-file .env.backup \
  ghcr.io/iemarjay/pg-r2-backup:latest \
  /app/scripts/restore.sh daily/panelsuite-20260416T020000Z.sql.gz.gpg
```

To DROP+CREATE the target DB first: `-e RESTORE_DROP_CREATE=1`.

List recent backups:

```bash
aws s3 ls s3://$R2_BUCKET/daily/ \
  --endpoint-url=https://$R2_ACCOUNT_ID.r2.cloudflarestorage.com
```

## Operational discipline

- **Test restore at least quarterly.** Untested backups are theatre.
- **Store `ENCRYPTION_PASSPHRASE` in two places** (e.g. 1Password + offline). Losing it = losing backups.
- **Monitor the healthcheck.** Silent failure is the #1 way backups rot.
- **Rotate R2 API tokens annually.**

## One-shot run (manual test)

```bash
docker run --rm --env-file .env.backup \
  ghcr.io/iemarjay/pg-r2-backup:latest \
  /app/scripts/backup.sh
```
