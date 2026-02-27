#!/bin/sh
set -e

echo "=== Backup Container Entrypoint ==="
echo "Starting backup service initialization..."
echo ""

# Container paths (defined in docker-compose)
BACKUP_DIR="/opt/backup"
ENV_FILE="/tmp/project_env.sh"
RUN_BACKUP_SCRIPT="$BACKUP_DIR/run-backup.sh"
CRONTAB_FILE="/etc/crontabs/root"

# 1. Capture Environment Variables
echo "[1/3] Exporting environment variables for cron..."
export > "$ENV_FILE"
chmod 600 "$ENV_FILE"
echo "  ✓ Environment file created: $ENV_FILE"
echo "  ✓ Permissions set to 600 (owner read/write only)"
echo "  ✓ Exported $(grep -c '=' "$ENV_FILE" || echo 0) environment variables"
echo ""

# 2. Setup Crontab
echo "[2/3] Setting up crontab..."
echo "  Schedule: $BACKUP_CRON_SCHEDULE"

# Construct the cron command to source env and run backup
CMD_STRING=". $ENV_FILE; echo 'Starting backup job...'; RESTIC_SNAPSHOT_TAG=daily_cron $RUN_BACKUP_SCRIPT"

# Overwrite crontab - don't persist previous schedules when restarting the service.
# We direct stdout/stderr to PID 1 (Docker logs)
CRON_ENTRY="$BACKUP_CRON_SCHEDULE $CMD_STRING > /proc/1/fd/1 2>/proc/1/fd/2"
echo "$CRON_ENTRY" > "$CRONTAB_FILE"

echo "  ✓ Crontab file written: $CRONTAB_FILE"
echo "  ✓ Crontab entry:"
echo "    $CRON_ENTRY"
echo ""

# 3. Start Crond
echo "[3/3] Starting cron daemon..."
echo "  Mode: foreground (-f)"
echo "  Log level: 2"
echo ""
echo "=== Backup service ready ==="
echo "Cron schedule: $BACKUP_CRON_SCHEDULE"

# Output current time and cron schedule time in UTC
CURRENT_UTC_TIME="$(date -u +"%H:%M")"
CRON_MINUTE="$(echo "$BACKUP_CRON_SCHEDULE" | awk '{print $1}')"
CRON_HOUR="$(echo "$BACKUP_CRON_SCHEDULE" | awk '{print $2}')"

if echo "$CRON_MINUTE" | grep -Eq '^[0-9]+$' && echo "$CRON_HOUR" | grep -Eq '^[0-9]+$'; then
  CRON_TIME_UTC=$(printf "%02d:%02d" "$CRON_HOUR" "$CRON_MINUTE")
else
  CRON_TIME_UTC="$CRON_HOUR:$CRON_MINUTE"
fi

echo "Current time (UTC): $CURRENT_UTC_TIME"
echo "Scheduled cron time (UTC): $CRON_TIME_UTC"

# Start cron in the foreground so the container stays alive
exec crond -f -l 2
