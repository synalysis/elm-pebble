defmodule IdeWeb.AuthController do
  use IdeWeb, :controller

  alias Ide.Auth

  @spec login(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def login(conn, _params) do
    if Auth.public_mode?() and conn.assigns[:current_user] do
      redirect(conn, to: ~p"/projects")
    else
      template =
        case Auth.mode() do
          :public_custom -> :login_custom
          _ -> :login_pebble
        end

      render(conn, template,
        page_title: "Log in",
        auth_mode: Auth.mode(),
        firebase_config: Auth.firebase_config(),
        step: custom_login_step(conn.params),
        email: custom_login_email(conn.params),
        login_link_ttl_days: Auth.login_link_ttl_days()
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
      has_firebase_token: is_binary(token) and token != "",
      app_store_publish_enabled: Auth.app_store_publish_enabled?()
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

  @spec email_continue(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def email_continue(conn, %{"email" => email}) when is_binary(email) do
    if Auth.public_custom_mode?() do
      email = Ide.Auth.User.normalize_email(email)

      case Auth.send_login_link(email) do
        :ok ->
          render(conn, :login_custom,
            page_title: "Check your email",
            auth_mode: Auth.mode(),
            firebase_config: Auth.firebase_config(),
            step: :sent,
            email: email,
            login_link_ttl_days: Auth.login_link_ttl_days()
          )

        {:error, :invalid_email} ->
          conn
          |> put_flash(:error, "Enter a valid email address.")
          |> redirect(to: ~p"/login")

        {:error, :delivery_failed} ->
          conn
          |> put_flash(:error, "Could not send the login email. Try again in a moment.")
          |> redirect(to: ~p"/login")
      end
    else
      conn |> put_status(:not_found) |> text("Not found")
    end
  end

  def email_continue(conn, _params) do
    conn |> put_flash(:error, "Email is required.") |> redirect(to: ~p"/login")
  end

  @spec email_verify(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def email_verify(conn, %{"token" => token}) when is_binary(token) do
    if Auth.public_custom_mode?() do
      case Auth.verify_login_token(token) do
        {:ok, user} ->
          conn
          |> renew_session()
          |> put_session(:user_id, user.id)
          |> delete_session(:firebase_id_token)
          |> delete_session(:firebase_id_token_exp)
          |> put_flash(:info, "You are now logged in.")
          |> redirect(to: ~p"/projects")

        {:error, :expired_token} ->
          conn
          |> put_flash(:error, "This login link has expired. Request a new one.")
          |> redirect(to: ~p"/login")

        {:error, :used_token} ->
          conn
          |> put_flash(:error, "This login link was already used. Request a new one.")
          |> redirect(to: ~p"/login")

        {:error, :invalid_token} ->
          conn
          |> put_flash(:error, "This login link is invalid. Request a new one.")
          |> redirect(to: ~p"/login")
      end
    else
      conn |> put_status(:not_found) |> text("Not found")
    end
  end

  def email_verify(conn, _params) do
    conn
    |> put_flash(:error, "Missing login link token.")
    |> redirect(to: ~p"/login")
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

  defp custom_login_step(%{"step" => "sent"}), do: :sent
  defp custom_login_step(_), do: :email

  defp custom_login_email(%{"email" => email}) when is_binary(email) do
    email |> String.trim() |> case do
      "" -> nil
      value -> Ide.Auth.User.normalize_email(value)
    end
  end

  defp custom_login_email(_), do: nil

  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end
end
