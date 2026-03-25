import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :argon2_elixir, t_cost: 1, m_cost: 8

# Runtime environment flag to run Task.start synchronously in tests
# This avoids sandbox issues with async database operations
Application.put_env(:acai, :no_async_tasks, true)

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
#
# HAVING PROBLEMS? You probably forgot `MIX_ENV=test mix test`
config :acai, Acai.Repo,
  username: "postgres",
  password: "postgres",
  # Set to `localhost` for ci runners & workflows
  hostname: System.get_env("POSTGRES_HOST", "db"),
  database: "acai_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# In test we don't send emails
config :acai, Acai.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

config :logger, :default_handler,
  filters: [
    remote_gl: {&:logger_filters.remote_gl/2, :stop},
    api_rejection: {&AcaiWeb.Api.RejectionLog.filter_api_rejection/2, :stop}
  ]

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
