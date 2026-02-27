#!/bin/sh
set -e

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Ensure a restic repository exists by using `restic cat config`
# Exit code 10 (or matching error text) means the repo is missing and should be initialized.
ensure_repo() {
    repo="$1"
    label="$2"

    if restic -r "$repo" cat config >/dev/null 2>&1; then
        log "$label repository exists at $repo."
        return 0
    else
        status=$?  # restic exit code

        # restic emits status 10 for 'repo doesn't exist'
        if [ "$status" -eq 10 ] || [ "$status" -eq 1 ]; then
            log "$label repository missing (exit $status). Initializing at $repo..."
            restic -r "$repo" init
            return 0
        fi

        log "☠️ run-backup.sh ERROR: cannot access $label repository at $repo (exit $status)."
        exit 1
    fi
}

# --- Initialization ---

ensure_repo "$RESTIC_LOCAL_REPO" "Local"
ensure_repo "$RESTIC_REMOTE_REPO" "Remote"

# --- Step 1: Backup to Local Disk ---

FILENAME="${POSTGRES_DB}_$(date +%Y%m%d_%H%M%S).dump"
log "Step 1: Streaming Database to LOCAL Repository..."

# Use RESTIC_SNAPSHOT_TAG env var, defaulting to "untagged"
SNAPSHOT_TAG="${RESTIC_SNAPSHOT_TAG:-untagged}"

# We target $RESTIC_LOCAL_REPO here
if ! restic backup \
    -r "$RESTIC_LOCAL_REPO" \
    --stdin-from-command \
    --stdin-filename "$FILENAME" \
    --tag "$SNAPSHOT_TAG" \
    --host "backup-container" \
    -- \
    pg_dump \
        -h "$POSTGRES_HOST" \
        -p "$POSTGRES_PORT" \
        -U "$POSTGRES_USER" \
        --format=custom \
        --no-owner \
        --no-acl \
        "$POSTGRES_DB"; then
    log "ERROR: Local backup failed!"
    exit 1
fi

log "Local backup successful."

# --- Step 2: Push to S3 ---

log "Step 2: Syncing (Copying) snapshots to REMOTE Repository..."

# set password for copy --from-repo
export RESTIC_FROM_PASSWORD="$RESTIC_PASSWORD"

# 'copy' transfers snapshots from one repo to another.
# It is smart: it only uploads chunks that S3 doesn't have yet.
if ! restic copy \
    --repo "$RESTIC_REMOTE_REPO" \
    --from-repo "$RESTIC_LOCAL_REPO"; then
    log "ERROR: Remote sync failed!"
    exit 1
fi

log "Sync to S3 successful."

# --- Step 3: Verify Integrity ---

log "Step 3: Verifying repository integrity..."

# Check Local
restic check \
    -r "$RESTIC_LOCAL_REPO"

# Check Remote
restic check \
    -r "$RESTIC_REMOTE_REPO"

log "Integrity verification complete."

# --- Step 4: Maintenance (Prune Both) ---

log "Step 4: Pruning old backups..."

# Prune Local
restic forget \
    -r "$RESTIC_LOCAL_REPO" \
    --keep-daily 7 \
    --prune

# Prune Remote
restic forget \
    -r "$RESTIC_REMOTE_REPO" \
    --keep-daily 7 \
    --keep-weekly 4 \
    --keep-monthly 12 \
    --prune

log "Maintenance complete. Job finished."

# --- Step 5: Heartbeat ---

if [ -n "$BACKUP_HEARTBEAT_URL" ]; then
    log "Sending heartbeat to $BACKUP_HEARTBEAT_URL ..."
    curl -fsS -m 10 --retry 3 "$BACKUP_HEARTBEAT_URL" > /dev/null || log "WARNING: Heartbeat failed."
fi
