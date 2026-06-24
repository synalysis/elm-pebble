defmodule IdeWeb.AuthHooks do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView

  alias Ide.Auth
  alias IdeWeb.WorkspaceLive.Types

  @spec on_mount(atom(), Types.wire_params(), Types.session_params(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()} | {:halt, Phoenix.LiveView.Socket.t()}
  def on_mount(:default, _params, session, socket) do
    user = Auth.get_user(session["user_id"])
    token = session["firebase_id_token"]
    token_exp = session["firebase_id_token_exp"]

    if user do
      Process.put(:ide_current_user, user)
    end

    socket =
      socket
      |> assign(:auth_mode, Auth.mode())
      |> assign(:current_user, user)
      |> assign(:firebase_id_token, token)
      |> assign(:firebase_id_token_exp, token_exp)
      |> assign(:firebase_config, Auth.firebase_config())

    if Auth.public_mode?() and is_nil(user) do
      {:halt, redirect(socket, to: "/login")}
    else
      {:cont, socket}
    end
  end
end
