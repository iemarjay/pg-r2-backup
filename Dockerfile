FROM alpine:3.20

RUN apk add --no-cache \
      postgresql16-client \
      aws-cli \
      gnupg \
      dcron \
      bash \
      curl \
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

ENTRYPOINT ["/app/scripts/entrypoint.sh"]
