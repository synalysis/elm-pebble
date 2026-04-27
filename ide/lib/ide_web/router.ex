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

  scope "/api", IdeWeb do
    pipe_through :api

    post "/mcp", McpController, :create
    post "/tokenize", TokenizerController, :create
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
