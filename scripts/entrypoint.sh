#!/bin/bash
set -euo pipefail

if [ "$#" -gt 0 ]; then
  # Allow one-shot runs: `docker run ... backup.sh` or `restore.sh ...`
  exec "$@"
fi

: "${BACKUP_CRON:?}"

CRON_ENV=/app/cron.env
printenv | grep -E '^(PG_|R2_|BACKUP_|ENCRYPTION_|HEALTHCHECK_|TZ=)' \
  | sed 's/^\(.*\)$/export \1/' \
  > "$CRON_ENV"

CRON_FILE=/etc/crontabs/root
{
  echo "SHELL=/bin/bash"
  echo "${BACKUP_CRON} . ${CRON_ENV}; /app/scripts/backup.sh >> /proc/1/fd/1 2>&1"
} > "$CRON_FILE"

echo "[entrypoint] cron installed: ${BACKUP_CRON}"
echo "[entrypoint] tz=${TZ:-UTC}"

exec crond -f -l 8
