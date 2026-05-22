defmodule IdeWeb.Plugs.FetchCurrentUser do
  @moduledoc false

  import Plug.Conn

  alias Ide.Auth

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    user = Auth.get_user(get_session(conn, :user_id))
    token = get_session(conn, :firebase_id_token)
    token_exp = get_session(conn, :firebase_id_token_exp)

    if user do
      Process.put(:ide_current_user, user)
    end

    conn
    |> assign(:current_user, user)
    |> assign(:firebase_id_token, token)
    |> assign(:firebase_id_token_exp, token_exp)
    |> assign(:auth_mode, Auth.mode())
    |> register_before_send(fn conn ->
      Process.delete(:ide_current_user)
      conn
    end)
  end
end
