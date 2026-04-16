#!/bin/bash
# Ops tool: pull a backup from R2, decrypt, and restore to a target Postgres.
#
# Usage:
#   docker run --rm -it --env-file .env.backup \
#     ghcr.io/amp10-technologies/pg-r2-backup:latest \
#     /app/scripts/restore.sh daily/panelsuite-20260416T020000Z.sql.gz.gpg
#
# The target DB (PG_DATABASE) must already exist and be empty, or pass
# RESTORE_DROP_CREATE=1 to have the script DROP and CREATE it first.

set -euo pipefail

KEY="${1:?Usage: restore.sh <object-key>  (e.g. daily/panelsuite-20260416T020000Z.sql.gz.gpg)}"

: "${PG_HOST:?}" "${PG_USER:?}" "${PG_PASSWORD:?}" "${PG_DATABASE:?}"
: "${R2_ACCOUNT_ID:?}" "${R2_BUCKET:?}" "${R2_ACCESS_KEY_ID:?}" "${R2_SECRET_ACCESS_KEY:?}"
: "${ENCRYPTION_PASSPHRASE:?}"

PG_PORT="${PG_PORT:-5432}"
ENDPOINT="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
TMP="/tmp/restore-$(basename "$KEY")"

export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="auto"
export PGPASSWORD="$PG_PASSWORD"

log() { echo "[$(date -u +%H:%M:%S)] $*"; }

log "Downloading s3://${R2_BUCKET}/${KEY}"
aws s3 cp "s3://${R2_BUCKET}/${KEY}" "$TMP" --endpoint-url="$ENDPOINT"

if [ "${RESTORE_DROP_CREATE:-0}" = "1" ]; then
  log "DROP + CREATE DATABASE ${PG_DATABASE}"
  psql --host="$PG_HOST" --port="$PG_PORT" --username="$PG_USER" --dbname=postgres \
    -c "DROP DATABASE IF EXISTS \"${PG_DATABASE}\";" \
    -c "CREATE DATABASE \"${PG_DATABASE}\";"
fi

log "Decrypting and restoring into ${PG_DATABASE}"
gpg --decrypt --batch --yes --passphrase "$ENCRYPTION_PASSPHRASE" "$TMP" \
  | gunzip \
  | psql --host="$PG_HOST" --port="$PG_PORT" --username="$PG_USER" --dbname="$PG_DATABASE" \
        --set ON_ERROR_STOP=on

rm -f "$TMP"
log "Restore complete"
