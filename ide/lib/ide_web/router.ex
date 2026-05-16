defmodule IdeWeb.Router do
  use IdeWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {IdeWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :wasm_emulator do
    plug :accepts, ["html"]
  end

  scope "/", IdeWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/projects/:id/export", ProjectExportController, :show
    live "/projects", ProjectsLive, :index
    live "/settings", SettingsLive, :index
    live "/projects/:slug/editor", WorkspaceLive, :editor
    live "/projects/:slug/resources", WorkspaceLive, :resources
    live "/projects/:slug/packages", WorkspaceLive, :packages
    live "/projects/:slug/debugger", WorkspaceLive, :debugger
    live "/projects/:slug/build", WorkspaceLive, :build
    live "/projects/:slug/publish", WorkspaceLive, :publish
    live "/projects/:slug/emulator", WorkspaceLive, :emulator
    live "/projects/:slug/settings", WorkspaceLive, :settings
  end

  scope "/", IdeWeb do
    pipe_through :wasm_emulator

    get "/wasm-emulator", WasmEmulatorController, :page
    get "/wasm-emulator/assets/*path", WasmEmulatorController, :asset
  end

  scope "/api", IdeWeb do
    pipe_through :api

    post "/mcp", McpController, :create
    post "/tokenize", TokenizerController, :create
    post "/emulator/launch", EmulatorController, :launch
    post "/emulator/:id/ping", EmulatorController, :ping
    post "/emulator/:id/install", EmulatorController, :install
    post "/emulator/:id/kill", EmulatorController, :kill
    get "/emulator/config-return", EmulatorController, :config_return
    get "/projects/:slug/companion/preferences", EmulatorController, :companion_preferences
    get "/emulator/:id/artifact", EmulatorController, :artifact
    get "/emulator/:id/ws/vnc", EmulatorController, :ws_vnc
    get "/emulator/:id/ws/phone", EmulatorController, :ws_phone
    get "/wasm-emulator/status", WasmEmulatorController, :status
    get "/wasm-emulator/projects/:slug/package", WasmEmulatorController, :package
    get "/wasm-emulator/projects/:slug/install-plan", WasmEmulatorController, :install_plan
    post "/wasm-emulator/projects/:slug/screenshot", WasmEmulatorController, :screenshot
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:ide, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: IdeWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
