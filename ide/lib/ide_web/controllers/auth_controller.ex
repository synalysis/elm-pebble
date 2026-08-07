defmodule IdeWeb.AuthController do
  use IdeWeb, :controller

  alias Ide.Auth
  alias Ide.Auth.EmailHash
  alias Ide.Auth.FirebaseTokenStore
  alias Ide.Auth.LoginBotDefense
  alias Ide.Auth.LoginRateLimit
  alias IdeWeb.AuthReturnTo
  alias IdeWeb.Types

  @spec login(Plug.Conn.t(), Types.wire_params()) :: Plug.Conn.t()
  def login(conn, params) do
    return_to = AuthReturnTo.peek(conn, params)
    conn = AuthReturnTo.put_session(conn, return_to)

    if Auth.public_mode?() and conn.assigns[:current_user] do
      redirect(conn, to: return_to)
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
        step: custom_login_step(params),
        email: custom_login_email(params),
        return_to: return_to,
        login_link_ttl_days: Auth.login_link_ttl_days(),
        turnstile_site_key: Auth.turnstile_site_key(),
        login_honeypot_field: LoginBotDefense.honeypot_field()
      )
    end
  end

  @spec status(Plug.Conn.t(), Types.wire_params()) :: Plug.Conn.t()
  def status(conn, _params) do
    user = conn.assigns[:current_user]
    token = conn.assigns[:firebase_id_token]
    token_exp = conn.assigns[:firebase_id_token_exp]

    json(conn, %{
      mode: Auth.mode(),
      logged_in: not is_nil(user),
      display_name: user && user.display_name,
      firebase_token_exp: token_exp,
      firebase_token_expired: Auth.token_expired?(token_exp),
      has_firebase_token: is_binary(token) and token != "",
      app_store_publish_enabled: Auth.app_store_publish_enabled?(),
      mail_delivery_configured: Auth.mail_delivery_configured?()
    })
  end

  @doc """
  Dead-view fallback for GitHub/Apple CloudPebble login.

  Publish uses popup login (COOP is disabled on that pane). If the popup fails,
  this page offers a Continue button so the user can retry with a fresh gesture.
  Redirect-based Firebase auth is unreliable on modern browsers that block
  third-party cookies when `authDomain` is a different site.
  """
  @spec firebase_bridge(Plug.Conn.t(), Types.wire_params()) :: Plug.Conn.t()
  def firebase_bridge(conn, params) when is_map(params) do
    provider = normalize_oauth_provider(Map.get(params, "provider"))
    return_to = AuthReturnTo.peek(conn, params)
    conn = AuthReturnTo.put_session(conn, return_to)

    render(conn, :firebase_bridge,
      page_title: "CloudPebble login",
      firebase_config: Auth.firebase_config(),
      provider: provider,
      provider_label: oauth_provider_label(provider),
      return_to: return_to
    )
  end

  @spec firebase(Plug.Conn.t(), Types.wire_params()) :: Plug.Conn.t()
  def firebase(conn, %{"id_token" => id_token} = params) do
    with {:ok, payload} <- Auth.verify_firebase_id_token(id_token),
         {:ok, user} <- Auth.upsert_firebase_user(payload) do
      token = String.trim(id_token)
      :ok = FirebaseTokenStore.put(user.id, token)
      {conn, return_to} = AuthReturnTo.take(conn, params)

      conn
      |> put_firebase_session(user, token)
      |> json(%{
        logged_in: true,
        email: payload["email"],
        display_name: user.display_name,
        redirect_to: return_to
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

  @spec email_continue(Plug.Conn.t(), Types.wire_params()) :: Plug.Conn.t()
  def email_continue(conn, params) when is_map(params) do
    if Auth.public_custom_mode?() do
      return_to = AuthReturnTo.peek(conn, params)
      conn = AuthReturnTo.put_session(conn, return_to)

      case Map.get(params, "email") do
        email when is_binary(email) ->
          email = Ide.Auth.User.normalize_email(email)

          cond do
            LoginBotDefense.bot_request?(params) ->
              render_login_sent(conn, email, return_to)

            not LoginBotDefense.turnstile_ok?(conn, params) ->
              render_login_sent(conn, email, return_to)

            login_rate_limited?(conn, email) ->
              render_login_sent(conn, email, return_to)

            true ->
              case Auth.send_login_link(email) do
                :ok ->
                  record_login_attempt(conn, email)
                  render_login_sent(conn, email, return_to)

                {:error, :invalid_email} ->
                  conn
                  |> put_flash(:error, "Enter a valid email address.")
                  |> redirect(to: AuthReturnTo.login_path(return_to))

                {:error, :mailer_not_configured} ->
                  conn
                  |> put_flash(
                    :error,
                    "Email login is not configured on this server. Contact the site administrator."
                  )
                  |> redirect(to: AuthReturnTo.login_path(return_to))

                {:error, :delivery_failed} ->
                  conn
                  |> put_flash(:error, "Could not send the login email. Try again in a moment.")
                  |> redirect(to: AuthReturnTo.login_path(return_to))
              end
          end

        _ ->
          conn
          |> put_flash(:error, "Email is required.")
          |> redirect(to: AuthReturnTo.login_path(return_to))
      end
    else
      conn |> put_status(:not_found) |> text("Not found")
    end
  end

  def email_continue(conn, _params) do
    conn |> put_flash(:error, "Email is required.") |> redirect(to: ~p"/login")
  end

  @spec email_verify(Plug.Conn.t(), Types.wire_params()) :: Plug.Conn.t()
  def email_verify(conn, %{"token" => token} = params) when is_binary(token) do
    if Auth.public_custom_mode?() do
      {conn, return_to} = AuthReturnTo.take(conn, params)

      case Auth.verify_login_token(token) do
        {:ok, user} ->
          conn
          |> renew_session()
          |> put_session(:user_id, user.id)
          |> delete_session(:firebase_id_token)
          |> delete_session(:firebase_id_token_exp)
          |> put_flash(:info, "You are now logged in.")
          |> redirect(to: return_to)

        {:error, :expired_token} ->
          conn
          |> put_flash(:error, "This login link has expired. Request a new one.")
          |> redirect(to: AuthReturnTo.login_path(return_to))

        {:error, :used_token} ->
          conn
          |> put_flash(:error, "This login link was already used. Request a new one.")
          |> redirect(to: AuthReturnTo.login_path(return_to))

        {:error, :invalid_token} ->
          conn
          |> put_flash(:error, "This login link is invalid. Request a new one.")
          |> redirect(to: AuthReturnTo.login_path(return_to))
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

  @spec refresh(Plug.Conn.t(), Types.wire_params()) :: Plug.Conn.t()
  def refresh(conn, %{"id_token" => id_token}) do
    with user when not is_nil(user) <- conn.assigns[:current_user],
         {:ok, payload} <- Auth.verify_firebase_id_token(id_token),
         true <- payload["localId"] == user.firebase_uid do
      token = String.trim(id_token)
      :ok = FirebaseTokenStore.put(user.id, token)

      conn
      |> put_session(:firebase_id_token_exp, Auth.token_exp(token))
      |> delete_session(:firebase_id_token)
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

  @spec logout(Plug.Conn.t(), Types.wire_params()) :: Plug.Conn.t()
  def logout(conn, _params) do
    FirebaseTokenStore.delete(get_session(conn, :user_id))
    FirebaseTokenStore.delete(get_session(conn, :firebase_user_id))

    conn
    |> renew_session()
    |> json(%{logged_in: false})
  end

  @spec delete_data(Plug.Conn.t(), Types.wire_params()) :: Plug.Conn.t()
  def delete_data(conn, _params) do
    if Auth.public_mode?() do
      case conn.assigns[:current_user] do
        %Ide.Auth.User{} = user ->
          case Auth.delete_user_data(user) do
            :ok ->
              FirebaseTokenStore.delete(user.id)

              conn
              |> renew_session()
              |> put_flash(:info, "Your account data has been deleted.")
              |> redirect(to: ~p"/login")

            {:error, reason} ->
              conn
              |> put_flash(:error, "Could not delete your data: #{inspect(reason)}")
              |> redirect(to: ~p"/projects")
          end

        _ ->
          conn |> put_status(:not_found) |> text("Not found")
      end
    else
      conn |> put_status(:not_found) |> text("Not found")
    end
  end

  @spec custom_login_step(map() | term()) :: term()

  defp custom_login_step(%{"step" => "sent"}), do: :sent
  defp custom_login_step(_), do: :email

  @spec custom_login_email(map() | term()) :: term()

  defp custom_login_email(%{"email" => email}) when is_binary(email) do
    email
    |> String.trim()
    |> case do
      "" -> nil
      value -> Ide.Auth.User.normalize_email(value)
    end
  end

  defp custom_login_email(_), do: nil

  @spec render_login_sent(Plug.Conn.t(), String.t(), String.t()) :: Plug.Conn.t()
  defp render_login_sent(conn, email, return_to) do
    render(conn, :login_custom,
      page_title: "Check your email",
      auth_mode: Auth.mode(),
      firebase_config: Auth.firebase_config(),
      step: :sent,
      email: email,
      return_to: return_to,
      login_link_ttl_days: Auth.login_link_ttl_days(),
      turnstile_site_key: Auth.turnstile_site_key(),
      login_honeypot_field: LoginBotDefense.honeypot_field()
    )
  end

  @spec login_rate_limited?(Plug.Conn.t(), String.t()) :: boolean()
  defp login_rate_limited?(conn, email) do
    not LoginRateLimit.allowed?(:ip, client_ip(conn)) or
      not LoginRateLimit.allowed?(:email, EmailHash.hash(email))
  end

  @spec record_login_attempt(Plug.Conn.t(), String.t()) :: :ok
  defp record_login_attempt(conn, email) do
    LoginRateLimit.record(:ip, client_ip(conn))
    LoginRateLimit.record(:email, EmailHash.hash(email))
  end

  @spec client_ip(Plug.Conn.t()) :: String.t()
  defp client_ip(conn) do
    conn.remote_ip
    |> :inet.ntoa()
    |> to_string()
  rescue
    _ -> "0.0.0.0"
  end

  @spec renew_session(Plug.Conn.t()) :: Plug.Conn.t()

  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  # Local mode: Firebase is only CloudPebble/App Store identity. Do not set
  # `user_id` or projects disappear (local projects are owner_id: nil).
  # Public modes: Firebase user is the IDE account.
  defp put_firebase_session(conn, user, token) do
    conn =
      if Auth.public_mode?() do
        conn
        |> renew_session()
        |> put_session(:user_id, user.id)
        |> delete_session(:firebase_user_id)
      else
        conn
        |> put_session(:firebase_user_id, user.id)
        |> delete_session(:user_id)
      end

    conn
    |> put_session(:firebase_id_token_exp, Auth.token_exp(token))
    # Full JWT stays in FirebaseTokenStore — cookie sessions cannot hold it reliably.
    |> delete_session(:firebase_id_token)
  end

  @spec normalize_oauth_provider(term()) :: String.t()
  defp normalize_oauth_provider(provider) when provider in ["github", "apple", "google"] do
    provider
  end

  defp normalize_oauth_provider(_), do: "github"

  @spec oauth_provider_label(String.t()) :: String.t()
  defp oauth_provider_label("apple"), do: "Apple"
  defp oauth_provider_label("google"), do: "Google"
  defp oauth_provider_label(_), do: "GitHub"
end
