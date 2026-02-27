#!/bin/bash
# Source this script to load environment secrets from 1Password
# Usage: source ./infra/environment.sh
#    or: . ./infra/environment.sh

# Determine project root (works whether sourced or executed)
if [ -n "${BASH_SOURCE[0]:-}" ]; then
  PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
else
  PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fi

ENV_OP_FILE="$PROJECT_ROOT/infra/.env.op"
ENV_OVERRIDES="$PROJECT_ROOT/infra/.env"

# Check dependencies
if ! command -v op >/dev/null 2>&1; then
  echo "Error: 1Password CLI (op) not found" >&2
  return 1
fi

if [ ! -f "$ENV_OP_FILE" ]; then
  echo "Error: $ENV_OP_FILE not found" >&2
  return 1
fi

if [ -f "$HOME/.env" ]; then
  # shellcheck source=/dev/null
  source "$HOME/.env"
fi

echo "Loading secrets from 1Password..."

OP_ARGS=(--no-masking --env-file "$ENV_OP_FILE")

# optional /infra/.env file may not exist, apply as overrides if present
if [ -f "$ENV_OVERRIDES" ]; then
  OP_ARGS+=(--env-file "$ENV_OVERRIDES")
fi

ENV_OUTPUT=$(op run "${OP_ARGS[@]}" -- env 2>&1)
OP_EXIT_CODE=$?

if [ $OP_EXIT_CODE -ne 0 ]; then
  echo "Error: Failed to load secrets from 1Password" >&2
  echo "$ENV_OUTPUT" >&2
  return 1
fi

# Export each variable from the op run output
while IFS= read -r line; do
  # Skip empty lines
  [ -z "$line" ] && continue

  # Only process lines that look like KEY=value
  if [[ "$line" =~ ^[A-Z_][A-Z0-9_]*= ]]; then
    export "$line"
  fi
done <<< "$ENV_OUTPUT"

export OP_SECRETS_LOADED=1
echo "✓ Secrets loaded successfully (will persist until you exit this shell session)"
