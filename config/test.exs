import Config

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

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :acai, AcaiWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "yO/qHj5W2gRUo81Q/UPSEBBEOYwXtf9z8zR5H6OIQRMRVhgJKMUsmYy6ZFiiCq8i",
  server: false

# In test we don't send emails
config :acai, Acai.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
