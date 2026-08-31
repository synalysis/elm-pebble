defmodule IdeWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :ide

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: {IdeWeb.Session, :options, []}]],
    longpoll: [connect_info: [session: {IdeWeb.Session, :options, []}]]

  socket "/socket", IdeWeb.UserSocket,
    websocket: [connect_info: [session: {IdeWeb.Session, :options, []}]],
    longpoll: [connect_info: [session: {IdeWeb.Session, :options, []}]]

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :ide,
    gzip: false,
    only: IdeWeb.static_paths(),
    # Required when workspace pages set COEP: require-corp (WASM + embedded noVNC chunks).
    headers: %{"cross-origin-resource-policy" => "same-origin"}

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :ide
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug IdeWeb.Plugs.RemoteIp
  plug IdeWeb.Plugs.Session
  plug IdeWeb.Plugs.CrossOriginIsolation
  plug IdeWeb.Router
end
