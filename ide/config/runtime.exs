import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/ide start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :ide, IdeWeb.Endpoint, server: true
end

github_oauth_client_id = System.get_env("GITHUB_OAUTH_CLIENT_ID")

config :ide, Ide.GitHub, oauth_client_id: github_oauth_client_id

config :ide, Ide.Emulator.Session,
  enabled: System.get_env("ELM_PEBBLE_EMBEDDED_EMULATOR", "true") not in ~w(0 false no off),
  qemu_bin: System.get_env("ELM_PEBBLE_QEMU_BIN"),
  qemu_image_root:
    System.get_env("ELM_PEBBLE_QEMU_IMAGE_ROOT") ||
      Path.expand(".pebble-sdk/SDKs/current/sdk-core/pebble", System.user_home!()),
  qemu_data_root: System.get_env("ELM_PEBBLE_QEMU_DATA_ROOT"),
  download_images:
    System.get_env("ELM_PEBBLE_QEMU_DOWNLOAD_IMAGES", "true") not in ~w(0 false no off),
  sdk_install_root: System.get_env("ELM_PEBBLE_SDK_INSTALL_ROOT"),
  sdk_core_version: System.get_env("ELM_PEBBLE_SDK_CORE_VERSION") || "4.9.169",
  sdk_core_metadata_url: System.get_env("ELM_PEBBLE_SDK_CORE_METADATA_URL"),
  sdk_core_archive_path: System.get_env("ELM_PEBBLE_SDK_CORE_ARCHIVE_PATH"),
  sdk_toolchain_archive_path: System.get_env("ELM_PEBBLE_SDK_TOOLCHAIN_ARCHIVE_PATH"),
  pypkjs_bin: System.get_env("ELM_PEBBLE_PYPKJS_BIN"),
  idle_timeout_ms:
    System.get_env("ELM_PEBBLE_EMULATOR_IDLE_TIMEOUT_MS", "300000")
    |> String.to_integer()

if config_env() == :prod do
  data_root = System.get_env("IDE_DATA_ROOT") || "/var/lib/ide"
  projects_root = System.get_env("PROJECTS_ROOT") || Path.join(data_root, "workspace_projects")
  settings_path = System.get_env("SETTINGS_FILE") || Path.join(data_root, "config/settings.json")

  settings_values =
    case File.read(settings_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, values} when is_map(values) -> values
          _ -> %{}
        end

      _ ->
        %{}
    end

  github_credentials_path =
    System.get_env("GITHUB_CREDENTIALS_FILE") ||
      Path.join(data_root, "config/github_credentials.json")

  database_path = System.get_env("DATABASE_PATH") || Path.join(data_root, "ide_prod.db")

  config :ide, Ide.Projects, projects_root: projects_root
  config :ide, Ide.Settings, settings_path: settings_path

  config :ide, Ide.GitHub,
    credentials_path: github_credentials_path,
    oauth_client_id: github_oauth_client_id

  config :ide, Ide.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

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

  host = System.get_env("PHX_HOST") || "example.com"

  configured_port =
    settings_values
    |> Map.get("mcp_http_port", 4000)
    |> then(fn
      port when is_integer(port) and port >= 1 and port <= 65_535 ->
        port

      port when is_binary(port) ->
        case Integer.parse(String.trim(port)) do
          {parsed, ""} when parsed >= 1 and parsed <= 65_535 -> parsed
          _ -> 4000
        end

      _ ->
        4000
    end)

  port = String.to_integer(System.get_env("PORT") || Integer.to_string(configured_port))

  config :ide, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :ide, IdeWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :ide, IdeWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :ide, IdeWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Also, you may need to configure the Swoosh API client of your choice if you
  # are not using SMTP. Here is an example of the configuration:
  #
  #     config :ide, Ide.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # For this example you need include a HTTP client required by Swoosh API client.
  # Swoosh supports Hackney and Finch out of the box:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Hackney
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
