#!/bin/bash
set -euo pipefail

# This script updates the `app` service to a target version, or `latest` if no version arg is provided.
# It does NOT update db, backup, or caddy services.
#
# Prerequisites:
#   - Load environment secrets first: source ./infra/environment.sh
#
# Examples:
#   source ./infra/environment.sh && ./infra/app/upgrade-app.sh
#   source ./infra/environment.sh && ./infra/app/upgrade-app.sh v1.1.1-canary.0
#   source ./infra/environment.sh && ./infra/app/upgrade-app.sh 1.1.1-canary.0

# Always finds project root relative to script location
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_FILE="$PROJECT_ROOT/infra/docker-compose.yml"
IMAGE_NAME="ghcr.io/acai-sh/service"

command -v docker >/dev/null || { echo "Error: docker not found"; exit 1; }
[ -f "$COMPOSE_FILE" ] || { echo "Error: $COMPOSE_FILE not found"; exit 1; }

# Use provided tag or default to "latest", stripping any 'v' prefix
VERSION_ARG="${1:-latest}"
export IMAGE_TAG_VERSION="${VERSION_ARG#v}"
FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG_VERSION}"

echo "Upgrading app to ${FULL_IMAGE}"

# Capture current image for rollback
CURRENT_CID=$(docker compose -f "$COMPOSE_FILE" ps -q app 2>/dev/null || true)
if [ -n "$CURRENT_CID" ]; then
  PREVIOUS_IMAGE=$(docker inspect --format '{{.Config.Image}}' "$CURRENT_CID" 2>/dev/null || true)
  echo "Current image: ${PREVIOUS_IMAGE:-unknown}"
else
  PREVIOUS_IMAGE=""
  echo "No existing app container found"
fi

# Authenticate with GitHub Container Registry
echo "Logging in to GitHub Container Registry..."
echo "$GITHUB_PAT" | docker login ghcr.io -u "$GITHUB_USER" --password-stdin

# Pull the new image (while old app is still running)
echo "Pulling image ${FULL_IMAGE}..."
docker compose -f "$COMPOSE_FILE" pull app

REMOTE_DIGEST=$(docker image inspect "$FULL_IMAGE" --format '{{index .RepoDigests 0}}' || true)
echo "Pulled image: $FULL_IMAGE"
echo "With digest: ${REMOTE_DIGEST:-unknown}"

# Backup database before running migrations
echo "Creating pre-migration backup..."
docker compose -f "$COMPOSE_FILE" exec -e RESTIC_SNAPSHOT_TAG=preupgrade backup /opt/backup/run-backup.sh

# Run migrations in a temporary container before stopping the old app
# This minimizes downtime - migrations run while old app still serves traffic
echo "Running database migrations..."
docker compose -f "$COMPOSE_FILE" run --rm --no-deps app /app/bin/migrate

echo "Starting new app version..."
START_TIME=$(date +%s%3N)
docker compose -f "$COMPOSE_FILE" up -d --no-deps --force-recreate app

echo "Waiting for app health..."
for i in {1..120}; do
  if response=$(curl -sf http://localhost:4000/_health 2>/dev/null); then
    END_TIME=$(date +%s%3N)
    DOWNTIME_MS=$((END_TIME - START_TIME))
    echo "App is healthy: $response"
    echo "Downtime: ${DOWNTIME_MS}ms"
    CID=$(docker compose -f "$COMPOSE_FILE" ps -q app)
    IMAGE_ID=$(docker inspect --format '{{.Image}}' "$CID")
    IMAGE_REF=$(docker inspect --format '{{index .Config.Image}}' "$CID")
    echo "App container image ref: $IMAGE_REF"
    echo "App container image id:  $IMAGE_ID"
    echo "Pruning unused images, containers, and networks."
    docker system prune -f
    echo "Done!"
    exit 0
  fi
  sleep 0.5
done

echo "ERROR - UPGRADE FAILURE - app failed to become healthy."

# Rollback to previous image if available
if [ -n "$PREVIOUS_IMAGE" ]; then
  echo "Rolling back to previous image: $PREVIOUS_IMAGE"
  export IMAGE_TAG_VERSION="${PREVIOUS_IMAGE#${IMAGE_NAME}:}"
  docker compose -f "$COMPOSE_FILE" up -d --no-deps --force-recreate app

  echo "Waiting for rollback health..."
  for i in {1..60}; do
    if curl -sf http://localhost:4000/_health 2>/dev/null; then
      echo "Rollback successful. Migrations were not rolled back."
      exit 1
    fi
    sleep 0.5
  done
  echo "Rollback also failed!"
fi

exit 1
