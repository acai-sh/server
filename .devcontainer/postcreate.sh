#!/usr/bin/env bash
set -euo pipefail

# Make sure ~/.local/bin is on PATH for this session
export PATH="$HOME/.local/bin:$PATH"

mix local.hex --force --if-missing
mix local.rebar --force --if-missing
mix deps.get

# creates the DB, runs migrations, and seeds.exs
mix ecto.setup
