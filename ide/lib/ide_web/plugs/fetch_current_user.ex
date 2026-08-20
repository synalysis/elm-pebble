defmodule IdeWeb.Plugs.FetchCurrentUser do
  @moduledoc false

  import Plug.Conn

  alias Ide.Auth

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    session = conn |> get_session() |> stringify_session_keys()
    user = Auth.get_user(get_session(conn, :user_id))
    firebase_account = Auth.get_user(get_session(conn, :firebase_user_id))
    token = Auth.resolve_firebase_session_token(session)
    token_exp = get_session(conn, :firebase_id_token_exp)

    if user do
      Process.put(:ide_current_user, user)
    end

    conn
    |> assign(:current_user, user)
    |> assign(:firebase_account, firebase_account)
    |> assign(:firebase_id_token, token)
    |> assign(:firebase_id_token_exp, token_exp)
    |> assign(:auth_mode, Auth.mode())
    |> register_before_send(fn conn ->
      Process.delete(:ide_current_user)
      conn
    end)
  end

  defp stringify_session_keys(session) when is_map(session) do
    Map.new(session, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end
end
