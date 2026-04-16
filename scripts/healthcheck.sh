#!/bin/bash
# Healthy if a backup succeeded within the last 25 hours (1500 minutes).
# backup.sh touches /app/last_success only after a successful upload.
find /app/last_success -mmin -1500 2>/dev/null | grep -q .
