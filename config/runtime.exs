import Config

# config/runtime.exs is executed for ALL ENVIRONMENTS
# including during test and releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# see .env.example for details
phx_port = String.to_integer(System.get_env("PHX_PORT", "4000"))
url_host = System.get_env("URL_HOST", "app.acai.sh")
url_path = System.get_env("URL_PATH", "/")
# fall back to secure defaults (ssl/https)
url_port = String.to_integer(System.get_env("URL_PORT", "443"))
url_scheme = System.get_env("URL_SCHEME", "https")

# ~~~~~~~~~~~~~~~~~~~~~~~
# 🔧 DEV / DEFAULT CONFIG
# ~~~~~~~~~~~~~~~~~~~~~~~

config :acai, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")
# Email sender configuration for white-labeling
config :acai, :mail_from_name, System.get_env("MAIL_FROM_NAME", "UnconfiguredMailer")
config :acai, :mail_from_email, System.get_env("MAIL_FROM_EMAIL", "noreply@example.com")

config :acai, AcaiWeb.Endpoint,
  # What phoenix uses to construct browser urls
  url: [host: url_host, port: url_port, scheme: url_scheme, path: url_path],
  # What the Phoenix app listens on internally, behind Caddy/Docker.
  http: [ip: {0, 0, 0, 0}, port: phx_port],
  secret_key_base: "UNSAFE_testerstest_/secret_key_base_do_not_use_UNSECURED++UNSAFE"

# ~~~~~~~~~~~~~~~
# 🧪 TEST CONFIG
# ~~~~~~~~~~~~~~~

if config_env() == :test do
  config :acai, AcaiWeb.Endpoint,
    # avoid port clash with running dev/prod
    http: [ip: {127, 0, 0, 1}, port: 4002]
end

# ~~~~~~~~~~~~~~~
# 🚀 PROD CONFIG
# ~~~~~~~~~~~~~~~

if config_env() == :prod do
  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  start_server? = System.get_env("START_SERVER") == "true"

  # Releases don't have `mix`
  # So you must pass START_SERVER=true when you run a self-contained erlang release.
  # i.e. in rel/overlays/server
  config :acai, AcaiWeb.Endpoint,
    secret_key_base: secret_key_base,
    server: start_server?

  database_url =
    System.get_env("DATABASE_URL") ||
      raise("""
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """)

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :acai, Acai.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE", "10")),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  config :acai, Acai.Mailer,
    adapter: Swoosh.Adapters.Mailgun,
    api_key: System.get_env("MAILGUN_API_KEY"),
    domain: System.get_env("MAILGUN_DOMAIN"),
    base_url: System.get_env("MAILGUN_BASE_URL")

  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
  config :swoosh, :api_client, Swoosh.ApiClient.Hackney
end
