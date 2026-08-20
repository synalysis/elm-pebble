defmodule IdeWeb.AuthHooks do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView

  alias Ide.Auth
  alias IdeWeb.AuthReturnTo
  alias IdeWeb.WorkspaceLive.Types

  @spec on_mount(atom(), Types.wire_params(), Types.session_params(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()} | {:halt, Phoenix.LiveView.Socket.t()}
  def on_mount(:default, params, session, socket) do
    user = Auth.get_user(session["user_id"])
    firebase_account = Auth.get_user(session["firebase_user_id"])
    token = Auth.resolve_firebase_session_token(session)
    token_exp = session["firebase_id_token_exp"]

    if user do
      Process.put(:ide_current_user, user)
    end

    socket =
      socket
      |> assign(:auth_mode, Auth.mode())
      |> assign(:current_user, user)
      |> assign(:firebase_account, firebase_account)
      |> assign(:firebase_id_token, token)
      |> assign(:firebase_id_token_exp, token_exp)
      |> assign(:firebase_config, Auth.firebase_config())

    if Auth.public_mode?() and is_nil(user) do
      return_to = live_return_to(socket, params)
      {:halt, redirect(socket, to: AuthReturnTo.login_path(return_to))}
    else
      {:cont, socket}
    end
  end

  @spec live_return_to(Phoenix.LiveView.Socket.t(), Types.wire_params()) :: String.t()
  defp live_return_to(socket, params) when is_map(params) do
    path =
      case socket.view do
        IdeWeb.ProjectsLive -> "/projects"
        IdeWeb.SettingsLive -> "/settings"
        IdeWeb.WorkspaceLive -> workspace_return_path(params)
        _ -> AuthReturnTo.default()
      end

    query =
      params
      |> Map.drop(["slug", "id", "resource_view"])
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
      |> URI.encode_query()

    AuthReturnTo.sanitize(if query == "", do: path, else: path <> "?" <> query)
  end

  defp live_return_to(_socket, _params), do: AuthReturnTo.default()

  defp workspace_return_path(%{"slug" => slug} = params) when is_binary(slug) do
    pane =
      cond do
        match?(%{"resource_view" => _}, params) -> "resources"
        true -> "editor"
      end

    "/projects/#{slug}/#{pane}"
  end

  defp workspace_return_path(_), do: AuthReturnTo.default()
end
