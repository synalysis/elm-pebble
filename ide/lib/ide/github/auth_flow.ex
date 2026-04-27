defmodule Ide.GitHub.AuthFlow do
  @moduledoc false

  alias Ide.GitHub.Client
  alias Ide.GitHub.Credentials

  @spec start_device_flow() :: {:ok, map()} | {:error, term()}
  def start_device_flow do
    with {:ok, result} <- Client.start_device_flow("repo"),
         true <- is_binary(result["device_code"]),
         true <- is_binary(result["user_code"]),
         true <- is_binary(result["verification_uri"]) do
      {:ok,
       %{
         "device_code" => result["device_code"],
         "user_code" => result["user_code"],
         "verification_uri" => result["verification_uri"],
         "verification_uri_complete" => result["verification_uri_complete"],
         "expires_in" => to_int(result["expires_in"], 900),
         "interval" => to_int(result["interval"], 5)
       }}
    else
      false -> {:error, :invalid_device_flow_payload}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec poll_and_connect(String.t()) :: {:ok, map()} | {:error, term()}
  def poll_and_connect(device_code) when is_binary(device_code) do
    with {:ok, token_payload} <- Client.poll_device_token(device_code),
         token when is_binary(token) <- token_payload["access_token"],
         {:ok, user} <- Client.fetch_user(token),
         :ok <-
           Credentials.put(%{
             "access_token" => token,
             "token_type" => token_payload["token_type"],
             "scope" => token_payload["scope"],
             "user_login" => user["login"],
             "user_id" => user["id"],
             "connected_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
             "last_checked_at" => DateTime.utc_now() |> DateTime.to_iso8601()
           }) do
      {:ok, Credentials.current()}
    else
      {:error, {:oauth_error, %{"error" => "authorization_pending"}} = error} -> {:error, error}
      {:error, {:oauth_error, %{"error" => "slow_down"}} = error} -> {:error, error}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_access_token_response}
    end
  end

  def poll_and_connect(_), do: {:error, :invalid_device_code}

  @spec disconnect() :: :ok | {:error, term()}
  def disconnect do
    Credentials.clear()
  end

  @spec status() :: map()
  def status do
    Credentials.current()
  end

  @spec oauth_client_configured?() :: boolean()
  def oauth_client_configured? do
    match?({:ok, _}, Client.oauth_client_id())
  end

  @spec to_int(term(), integer()) :: integer()
  defp to_int(value, _fallback) when is_integer(value), do: value

  defp to_int(value, fallback) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> fallback
    end
  end

  defp to_int(_value, fallback), do: fallback
end
