# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :ide,
  ecto_repos: [Ide.Repo],
  generators: [timestamp_type: :utc_datetime]

config :ide, Ide.Projects, projects_root: Path.expand("../workspace_projects", __DIR__)

config :ide, :diagnostics_provider, Ide.Diagnostics.PlaceholderProvider

config :ide, Ide.Compiler,
  elmc_root: Path.expand("../../elmc", __DIR__),
  elm_ex_root: Path.expand("../../elm_ex", __DIR__)

config :ide, Ide.Packages,
  provider_order: [:official, :mirror],
  providers: [
    official: [module: Ide.Packages.OfficialProvider, base_url: "https://package.elm-lang.org"],
    mirror: [module: Ide.Packages.MirrorProvider, base_url: "https://dark.elm.dmy.fr"]
  ],
  watch_forbidden_packages: ~w(elm/html elm/browser elm/virtual-dom),
  index_disk_cache: true

config :ide, Ide.PebbleToolchain,
  template_app_root: Path.expand("../priv/pebble_app_template", __DIR__),
  emulator_target: "basalt",
  emulator_targets: ~w(aplite basalt chalk diorite emery flint gabbro)

config :ide, Ide.Screenshots,
  storage_root: Path.expand("../priv/static/screenshots", __DIR__),
  public_prefix: "/screenshots"

config :ide, Ide.PublishManifest, output_root: Path.expand("../priv/publish_manifests", __DIR__)

config :ide, Ide.Settings, settings_path: Path.expand("../priv/ide_settings.json", __DIR__)

config :ide, Ide.GitHub,
  credentials_path: Path.expand("../priv/github_credentials.json", __DIR__),
  oauth_client_id: nil

config :ide, Ide.Formatter,
  semantics_pipeline: true,
  semantic_edit_ops: true

config :ide, Ide.Mcp.Tools,
  trace_policy: [
    warn_count: 200,
    warn_bytes: 50 * 1024 * 1024,
    keep_latest: 50,
    target_keep_latest: 50
  ]

# Configures the endpoint
config :ide, IdeWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: IdeWeb.ErrorHTML, json: IdeWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Ide.PubSub,
  live_view: [signing_salt: "9NKpMiE3"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :ide, Ide.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  ide: [
    args:
      ~w(js/app.js --bundle --format=esm --splitting --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  ide: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
