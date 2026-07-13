defmodule Ide.Auth.LoginBotDefense do
  @moduledoc """
  Honeypot and Cloudflare Turnstile checks for the magic-link login form.
  """

  @honeypot_field "organization"
  @turnstile_verify_url "https://challenges.cloudflare.com/turnstile/v0/siteverify"

  @type login_form_params :: %{optional(String.t()) => String.t() | boolean() | nil}

  @spec honeypot_field() :: String.t()
  def honeypot_field, do: @honeypot_field

  @spec bot_request?(login_form_params()) :: boolean()
  def bot_request?(params) when is_map(params) do
    params
    |> Map.get(@honeypot_field, "")
    |> to_string()
    |> String.trim()
    |> case do
      "" -> false
      _ -> true
    end
  end

  @spec turnstile_configured?() :: boolean()
  def turnstile_configured? do
    secret = turnstile_secret_key()
    is_binary(secret) and secret != ""
  end

  @spec turnstile_site_key() :: String.t() | nil
  def turnstile_site_key do
    Application.get_env(:ide, Ide.Auth, [])
    |> Keyword.get(:turnstile_site_key)
    |> normalize_key()
  end

  @spec turnstile_ok?(Plug.Conn.t(), login_form_params()) :: boolean()
  def turnstile_ok?(conn, params) when is_map(params) do
    if turnstile_configured?() do
      token =
        params
        |> Map.get("cf-turnstile-response", "")
        |> to_string()
        |> String.trim()

      if token == "" do
        false
      else
        verify_turnstile_token(conn, token)
      end
    else
      true
    end
  end

  @spec verify_turnstile_token(Plug.Conn.t(), String.t()) :: boolean()
  defp verify_turnstile_token(conn, token) do
    body = %{
      secret: turnstile_secret_key(),
      response: token,
      remoteip: client_ip(conn)
    }

    case Req.post(@turnstile_verify_url, form: body, receive_timeout: 5_000) do
      {:ok, %{status: 200, body: %{"success" => true}}} -> true
      _ -> false
    end
  end

  @spec client_ip(Plug.Conn.t()) :: String.t()
  defp client_ip(conn) do
    conn.remote_ip
    |> :inet.ntoa()
    |> to_string()
  rescue
    _ -> "0.0.0.0"
  end

  @spec turnstile_secret_key() :: String.t() | nil
  defp turnstile_secret_key do
    Application.get_env(:ide, Ide.Auth, [])
    |> Keyword.get(:turnstile_secret_key)
    |> normalize_key()
  end

  @spec normalize_key(String.t() | nil) :: String.t() | nil
  defp normalize_key(key) when is_binary(key) do
    case String.trim(key) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_key(_), do: nil
end
