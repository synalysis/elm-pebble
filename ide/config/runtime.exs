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

config :ide, Ide.Auth,
  mode:
    (case String.downcase(System.get_env("IDE_AUTH_MODE", "local") || "local") do
       "public_pebble" -> :public_pebble
       "public_custom" -> :public_custom
       "public" -> :public_pebble
       "local" -> :local
       _ -> :local
     end),
  firebase_api_key:
    System.get_env("IDE_FIREBASE_API_KEY") || "AIzaSyBZ9Cdvwwv9At2lPmc8TxyyEqSXGXejGvc",
  firebase_auth_domain:
    System.get_env("IDE_FIREBASE_AUTH_DOMAIN") || "coreapp-ce061.firebaseapp.com",
  firebase_project_id: System.get_env("IDE_FIREBASE_PROJECT_ID") || "coreapp-ce061",
  firebase_storage_bucket:
    System.get_env("IDE_FIREBASE_STORAGE_BUCKET") || "coreapp-ce061.firebasestorage.app",
  firebase_messaging_sender_id:
    System.get_env("IDE_FIREBASE_MESSAGING_SENDER_ID") || "460977838956",
  firebase_app_id:
    System.get_env("IDE_FIREBASE_APP_ID") || "1:460977838956:web:9a11a68ec78008fe303149",
  appstore_api_base:
    System.get_env("IDE_APPSTORE_API_BASE") || "https://appstore-api.repebble.com",
  login_link_ttl_days:
    (System.get_env("IDE_LOGIN_LINK_TTL_DAYS") || "30")
    |> String.to_integer(),
  email_hash_pepper: System.get_env("IDE_EMAIL_HASH_PEPPER")

config :ide, Ide.Emulator.SlotLimiter,
  max_slots:
    (System.get_env("ELM_PEBBLE_EMULATOR_MAX_SLOTS") || "8")
    |> String.to_integer()
    |> max(1),
  acquire_timeout_ms:
    (System.get_env("ELM_PEBBLE_EMULATOR_ACQUIRE_TIMEOUT_MS") || "600000")
    |> String.to_integer()
    |> max(1_000)

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

# Optional SMTP for any environment (dev/prod). When SMTP_RELAY is set, magic-link
# emails are sent through SMTP instead of the Swoosh Local adapter / dev mailbox.
if smtp_relay = System.get_env("SMTP_RELAY") do
  smtp_port = String.to_integer(System.get_env("SMTP_PORT") || "587")

  smtp_ssl =
    System.get_env("SMTP_SSL") in ~w(1 true yes) or
      (is_nil(System.get_env("SMTP_SSL")) and smtp_port == 465)

  smtp_tls =
    case System.get_env("SMTP_TLS") do
      "never" -> :never
      _ when smtp_ssl -> :never
      _ -> :always
    end

  smtp_tls_hostname = System.get_env("SMTP_TLS_HOSTNAME") || smtp_relay
  smtp_sni = String.to_charlist(smtp_tls_hostname)

  smtp_hostname_check = [
    match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
  ]

  smtp_verify_options =
    case :public_key.cacerts_get() do
      cacerts when is_list(cacerts) and cacerts != [] ->
        [
          verify: :verify_peer,
          cacerts: cacerts,
          server_name_indication: smtp_sni,
          hostname: smtp_tls_hostname,
          depth: 99,
          customize_hostname_check: smtp_hostname_check
        ]

      _ ->
        cacertfile =
          Enum.find(
            [
              "/etc/ssl/cert.pem",
              "/etc/pki/tls/certs/ca-bundle.crt",
              "/etc/ssl/certs/ca-certificates.crt"
            ],
            &File.regular?/1
          )

        if cacertfile do
          [
            verify: :verify_peer,
            cacertfile: cacertfile,
            server_name_indication: smtp_sni,
            hostname: smtp_tls_hostname,
            depth: 99,
            customize_hostname_check: smtp_hostname_check
          ]
        else
          []
        end
    end

  config :ide, Ide.Mailer,
    adapter: Swoosh.Adapters.SMTP,
    relay: smtp_relay,
    username: System.get_env("SMTP_USERNAME"),
    password: System.get_env("SMTP_PASSWORD"),
    port: smtp_port,
    tls: smtp_tls,
    auth: if(System.get_env("SMTP_USERNAME"), do: :always, else: :never),
    ssl: smtp_ssl,
    tls_options: smtp_verify_options,
    ssl_options: smtp_verify_options,
    retries: 1,
    no_mx_lookups: true
end

if config_env() == :prod do
  data_root = System.get_env("IDE_DATA_ROOT") || "/var/lib/ide"
  projects_root = System.get_env("PROJECTS_ROOT") || Path.join(data_root, "workspace_projects")

  auth_mode = System.get_env("IDE_AUTH_MODE", "local") |> String.downcase()
  public_mode = auth_mode in ["public", "public_pebble", "public_custom"]

  settings_values =
    if public_mode do
      %{}
    else
      settings_path =
        System.get_env("SETTINGS_FILE") || Path.join(data_root, "config/settings.json")

      case File.read(settings_path) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, values} when is_map(values) -> values
            _ -> %{}
          end

        _ ->
          %{}
      end
    end

  github_credentials_path =
    System.get_env("GITHUB_CREDENTIALS_FILE") ||
      Path.join(data_root, "config/github_credentials.json")

  repo_adapter = Ide.RepoSelector.adapter()
  repo_module = Ide.RepoSelector.repo()

  config :ide,
    ecto_adapter: repo_adapter,
    ecto_repos: [repo_module],
    repo_module: repo_module

  config :ide, Ide.Projects, projects_root: projects_root
  config :ide, Ide.Settings, data_root: data_root

  config :ide, Ide.GitHub,
    credentials_path: github_credentials_path,
    oauth_client_id: github_oauth_client_id

  config repo_module, Ide.DatabaseConfig.prod_repo_config(repo_adapter)

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

  auth_mode = String.downcase(System.get_env("IDE_AUTH_MODE", "local") || "local")

  mail_from =
    System.get_env("IDE_MAIL_FROM") ||
      "noreply@#{host}"

  config :ide, Ide.Auth,
    login_link_ttl_days:
      (System.get_env("IDE_LOGIN_LINK_TTL_DAYS") || "30")
      |> String.to_integer(),
    mail_from: mail_from,
    email_hash_pepper: System.get_env("IDE_EMAIL_HASH_PEPPER")

  if is_nil(System.get_env("SMTP_RELAY")) and auth_mode == "public_custom" do
    raise """
    SMTP_RELAY is required when IDE_AUTH_MODE=public_custom in production.

    Production disables Swoosh local mail storage, so magic-link login cannot send email
    without SMTP. Configure at least:

        SMTP_RELAY=smtp.example.com
        SMTP_PORT=587
        SMTP_USERNAME=...
        SMTP_PASSWORD=...
        IDE_MAIL_FROM=noreply@your-domain
        PHX_HOST=your-domain

    For port 465, set SMTP_PORT=465 (implicit TLS is selected automatically).
    """
  end
end

if config_env() == :test do
  config :ide, Ide.Auth, mode: :local
end
