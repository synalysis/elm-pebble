defmodule IdeWeb.Plugs.FetchCurrentUser do
  @moduledoc false

  import Plug.Conn

  alias Ide.Auth

  @spec init(term()) :: term()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), term()) :: Plug.Conn.t()
  def call(conn, _opts) do
    user = Auth.get_user(get_session(conn, :user_id))
    token = get_session(conn, :firebase_id_token)
    token_exp = get_session(conn, :firebase_id_token_exp)

    conn
    |> assign(:current_user, user)
    |> assign(:firebase_id_token, token)
    |> assign(:firebase_id_token_exp, token_exp)
    |> assign(:auth_mode, Auth.mode())
  end
end
