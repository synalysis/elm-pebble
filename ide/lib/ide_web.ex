defmodule IdeWeb do
  @moduledoc """
  The entrypoint for defining your web interface, such
  as controllers, components, channels, and so on.

  This can be used in your application as:

      use IdeWeb, :controller
      use IdeWeb, :html

  The definitions below will be executed for every controller,
  component, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define additional modules and import
  those modules here.
  """

  @spec static_paths() :: term()
  def static_paths,
    do:
      ~w(assets fonts images screenshots favicon.ico favicon.svg favicon-96x96.png apple-touch-icon.png site.webmanifest web-app-manifest-192x192.png web-app-manifest-512x512.png robots.txt)

  @spec router() :: term()
  def router do
    quote do
      use Phoenix.Router, helpers: false

      # Import common connection and controller functions to use in pipelines
      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  @spec channel() :: term()
  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  @spec controller() :: term()
  def controller do
    quote do
      use Phoenix.Controller,
        formats: [:html, :json],
        layouts: [html: IdeWeb.Layouts]

      use Gettext, backend: IdeWeb.Gettext

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  @spec live_view() :: term()
  def live_view do
    quote do
      use Phoenix.LiveView,
        layout: {IdeWeb.Layouts, :app}

      unquote(html_helpers())
    end
  end

  @spec live_component() :: term()
  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(html_helpers())
    end
  end

  @spec html() :: term()
  def html do
    quote do
      use Phoenix.Component

      # Import convenience functions from controllers
      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      # Include general helpers for rendering HTML
      unquote(html_helpers())
    end
  end

  @spec html_helpers() :: term()
  defp html_helpers do
    quote do
      # Translation
      use Gettext, backend: IdeWeb.Gettext

      # HTML escaping functionality
      import Phoenix.HTML
      # Core UI components
      import IdeWeb.CoreComponents

      # Shortcut for generating JS commands
      alias Phoenix.LiveView.JS

      # Routes generation with the ~p sigil
      unquote(verified_routes())
    end
  end

  @spec verified_routes() :: term()
  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: IdeWeb.Endpoint,
        router: IdeWeb.Router,
        statics: IdeWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/live_view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
