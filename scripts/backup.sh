#!/bin/bash
set -euo pipefail

: "${PG_HOST:?}" "${PG_USER:?}" "${PG_PASSWORD:?}" "${PG_DATABASE:?}"
: "${R2_ACCOUNT_ID:?}" "${R2_BUCKET:?}" "${R2_ACCESS_KEY_ID:?}" "${R2_SECRET_ACCESS_KEY:?}"
: "${ENCRYPTION_PASSPHRASE:?}"

PG_PORT="${PG_PORT:-5432}"
PREFIX="${BACKUP_NAME_PREFIX:-backup}"
HEALTHCHECK_URL="${HEALTHCHECK_URL:-}"

TS=$(date -u +%Y%m%dT%H%M%SZ)
DOW=$(date -u +%u)   # 1-7, Mon=1 Sun=7
DOM=$(date -u +%d)   # 01-31
FILE="${PREFIX}-${TS}.sql.gz.gpg"
TMP="/tmp/${FILE}"

ENDPOINT="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"

export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="auto"
export PGPASSWORD="$PG_PASSWORD"

log() { echo "[$(date -u +%H:%M:%S)] $*"; }
fail() { log "ERROR: $*"; rm -f "$TMP"; exit 1; }

ping_healthcheck() {
  [ -z "$HEALTHCHECK_URL" ] && return 0
  local suffix="${1:-}"
  curl -fsS -m 10 --retry 3 -o /dev/null "${HEALTHCHECK_URL}${suffix}" || log "healthcheck ping failed (non-fatal)"
}

ping_healthcheck "/start" || true

log "Dumping ${PG_DATABASE} from ${PG_HOST}:${PG_PORT}"
pg_dump \
  --host="$PG_HOST" \
  --port="$PG_PORT" \
  --username="$PG_USER" \
  --dbname="$PG_DATABASE" \
  --no-owner \
  --no-privileges \
  --format=plain \
  | gzip -9 \
  | gpg --symmetric --batch --yes --passphrase "$ENCRYPTION_PASSPHRASE" --cipher-algo AES256 --output "$TMP" \
  || fail "dump pipeline failed"

SIZE=$(stat -c%s "$TMP" 2>/dev/null || stat -f%z "$TMP")
[ "$SIZE" -gt 0 ] || fail "dump is empty"
log "Dump ready: ${SIZE} bytes"

upload() {
  local dest="$1"
  log "Uploading to s3://${R2_BUCKET}/${dest}"
  aws s3 cp "$TMP" "s3://${R2_BUCKET}/${dest}" \
    --endpoint-url="$ENDPOINT" \
    --only-show-errors \
    || fail "upload to ${dest} failed"
}

upload "daily/${FILE}"
[ "$DOW" = "7" ] && upload "weekly/${FILE}"
[ "$DOM" = "01" ] && upload "monthly/${FILE}"

rm -f "$TMP"
log "Backup complete"
ping_healthcheck ""
