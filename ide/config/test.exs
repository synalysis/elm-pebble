import Config

config :ide, Ide.Paths, repo_root: Path.expand("../..", __DIR__)

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :ide, Ide.Repo.Sqlite,
  database: Path.expand("../ide_test#{System.get_env("MIX_TEST_PARTITION")}.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :ide, IdeWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  url: [host: "localhost", port: 4002, scheme: "http"],
  secret_key_base: "b6ipsOJm6FpX685mhXpMwlEbam0P2ZpFfXx6N36lpKjaWuqefeD2xNfzsHxGhZ/8",
  server: false

config :ide, Ide.Auth, login_link_ttl_days: 30

# In test we don't send emails
config :ide, Ide.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

config :ide, Ide.Packages, index_disk_cache: false

# Keep companion bootstrap synchronous in tests (assertions run immediately after debugger-start).
config :ide, :debugger_async_companion_bootstrap, false

# Run debugger start inline in tests so LiveView assertions see a finished bootstrap.
config :ide, :debugger_sync_bootstrap, true

# Apply HTTP follow-ups synchronously in tests (deterministic Agent state).
config :ide, :debugger_async_http_followups, false

# Deliver AppMessage subscription effects synchronously in tests.
config :ide, :debugger_async_protocol_delivery, false

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
