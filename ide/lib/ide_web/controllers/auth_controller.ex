defmodule IdeWeb.AuthController do
  use IdeWeb, :controller

  alias Ide.Auth

  @spec login(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def login(conn, _params) do
    if Auth.public_mode?() and conn.assigns[:current_user] do
      redirect(conn, to: ~p"/projects")
    else
      render(conn, :login,
        page_title: "Log in",
        auth_mode: Auth.mode(),
        firebase_config: Auth.firebase_config()
      )
    end
  end

  @spec status(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def status(conn, _params) do
    user = conn.assigns[:current_user]
    token = conn.assigns[:firebase_id_token]
    token_exp = conn.assigns[:firebase_id_token_exp]

    json(conn, %{
      mode: Auth.mode(),
      logged_in: not is_nil(user),
      email: user && user.email,
      display_name: user && user.display_name,
      firebase_token_exp: token_exp,
      firebase_token_expired: Auth.token_expired?(token_exp),
      has_firebase_token: is_binary(token) and token != ""
    })
  end

  @spec firebase(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def firebase(conn, %{"id_token" => id_token}) do
    with {:ok, payload} <- Auth.verify_firebase_id_token(id_token),
         {:ok, user} <- Auth.upsert_firebase_user(payload) do
      conn
      |> renew_session()
      |> put_session(:user_id, user.id)
      |> put_session(:firebase_id_token, String.trim(id_token))
      |> put_session(:firebase_id_token_exp, Auth.token_exp(id_token))
      |> json(%{
        logged_in: true,
        email: user.email,
        display_name: user.display_name,
        redirect_to: "/projects"
      })
    else
      {:error, reason} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Firebase login failed: #{inspect(reason)}"})
    end
  end

  def firebase(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "Missing id_token"})
  end

  @spec refresh(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def refresh(conn, %{"id_token" => id_token}) do
    with user when not is_nil(user) <- conn.assigns[:current_user],
         {:ok, payload} <- Auth.verify_firebase_id_token(id_token),
         true <- payload["localId"] == user.firebase_uid do
      conn
      |> put_session(:firebase_id_token, String.trim(id_token))
      |> put_session(:firebase_id_token_exp, Auth.token_exp(id_token))
      |> json(%{ok: true})
    else
      nil -> conn |> put_status(:unauthorized) |> json(%{error: "Not logged in"})
      false -> conn |> put_status(:unauthorized) |> json(%{error: "Token user mismatch"})
      {:error, reason} -> conn |> put_status(:unauthorized) |> json(%{error: inspect(reason)})
    end
  end

  def refresh(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "Missing id_token"})
  end

  @spec logout(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def logout(conn, _params) do
    conn
    |> renew_session()
    |> json(%{logged_in: false})
  end

  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end
end
