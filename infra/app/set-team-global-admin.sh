#!/bin/bash
set -euo pipefail

# Updates a team's global_admin flag through the running release.
#
# Prerequisites:
#   - Load environment secrets first: source ./infra/environment.sh
#   - The `app` container must already be running
#
# Examples:
#   source ./infra/environment.sh && ./infra/app/set-team-global-admin.sh admin true
#   source ./infra/environment.sh && ./infra/app/set-team-global-admin.sh admin false --yes

usage() {
  cat <<'EOF'
Usage:
  ./infra/app/set-team-global-admin.sh TEAM_NAME true|false [--yes]

Options:
  --yes     Skip the interactive confirmation prompt
  --help    Show this help text

Notes:
  - TEAM_NAME is normalized to lowercase to match the teams.name storage format.
  - This script uses the running app release and Ecto, not raw SQL.
EOF
}

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_FILE="$PROJECT_ROOT/infra/docker-compose.yml"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

command -v docker >/dev/null || { echo "Error: docker not found" >&2; exit 1; }
docker compose version >/dev/null 2>&1 || {
  echo "Error: docker compose not available" >&2
  exit 1
}
[ -f "$COMPOSE_FILE" ] || { echo "Error: $COMPOSE_FILE not found" >&2; exit 1; }

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  usage >&2
  exit 1
fi

TEAM_NAME="$1"
GLOBAL_ADMIN_RAW="$2"
CONFIRM_FLAG="${3:-}"
TEAM_NAME="$(printf '%s' "$TEAM_NAME" | tr '[:upper:]' '[:lower:]')"

case "$GLOBAL_ADMIN_RAW" in
  true|TRUE|True|1|on|ON)
    GLOBAL_ADMIN="true"
    ;;
  false|FALSE|False|0|off|OFF)
    GLOBAL_ADMIN="false"
    ;;
  *)
    echo "Error: second argument must be true or false" >&2
    exit 1
    ;;
esac

if [ "$CONFIRM_FLAG" != "" ] && [ "$CONFIRM_FLAG" != "--yes" ]; then
  echo "Error: unsupported option '$CONFIRM_FLAG'" >&2
  exit 1
fi

if [ -z "$TEAM_NAME" ]; then
  echo "Error: team name must not be blank" >&2
  exit 1
fi

case "$TEAM_NAME" in
  *[!a-z0-9_-]*)
    echo "Error: team name must contain only letters, numbers, hyphens, and underscores" >&2
    exit 1
    ;;
esac

APP_CID="$(docker compose -f "$COMPOSE_FILE" ps -q app 2>/dev/null || true)"

if [ -z "$APP_CID" ]; then
  echo "Error: app container is not running. Start it before using this script." >&2
  exit 1
fi

if [ "$CONFIRM_FLAG" != "--yes" ]; then
  printf "Set teams.global_admin=%s for team '%s'? [y/N] " "$GLOBAL_ADMIN" "$TEAM_NAME"
  read -r reply

  case "$reply" in
    y|Y|yes|YES)
      ;;
    *)
      echo "Cancelled"
      exit 1
      ;;
  esac
fi

docker compose -f "$COMPOSE_FILE" exec -T \
  app /app/bin/acai rpc '
alias Acai.Repo
alias Acai.Teams.Team

team_name = "'"$TEAM_NAME"'"
global_admin = '"$GLOBAL_ADMIN"'

case Repo.get_by(Team, name: team_name) do
  nil ->
    IO.puts(:stderr, "No team found with name=#{inspect(team_name)}")
    System.halt(1)

  %Team{} = team when team.global_admin == global_admin ->
    IO.puts("No change needed: team=#{team.name} global_admin=#{team.global_admin}")

  %Team{} = team ->
    # dashboard.AUTH.1
    # dashboard.AUTH.1-1
    case team |> Team.trusted_changeset(%{global_admin: global_admin}) |> Repo.update() do
      {:ok, updated_team} ->
        IO.puts("Updated team=#{updated_team.name} global_admin=#{updated_team.global_admin}")

      {:error, changeset} ->
        IO.puts(:stderr, "Failed to update team=#{team.name}")
        IO.inspect(changeset.errors, label: "errors", stderr: true)
        System.halt(1)
    end
end
'
