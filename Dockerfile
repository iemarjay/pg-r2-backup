FROM alpine:3.20

RUN apk add --no-cache \
      postgresql16-client \
      aws-cli \
      gnupg \
      dcron \
      bash \
      tzdata \
      ca-certificates

WORKDIR /app

COPY scripts/ /app/scripts/
COPY crontab.template /app/crontab.template

RUN chmod +x /app/scripts/*.sh

ENV BACKUP_CRON="0 2 * * *" \
    PG_PORT=5432 \
    BACKUP_NAME_PREFIX=backup \
    TZ=UTC

HEALTHCHECK --interval=6h --timeout=5s --retries=1 \
  CMD ["/app/scripts/healthcheck.sh"]

ENTRYPOINT ["/app/scripts/entrypoint.sh"]
