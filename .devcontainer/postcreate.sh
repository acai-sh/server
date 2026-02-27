#!/usr/bin/env bash
set -euo pipefail

# Make sure ~/.local/bin is on PATH for this session
export PATH="$HOME/.local/bin:$PATH"

# Elixir basics (idempotent)
mix local.hex --force --if-missing
mix local.rebar --force --if-missing
mix deps.get
mix ecto.setup
