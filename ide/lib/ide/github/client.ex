defmodule Ide.GitHub.Client do
  @moduledoc false

  @device_code_path "/login/device/code"
  @token_path "/login/oauth/access_token"
  @user_path "/user"
  @device_grant_type "urn:ietf:params:oauth:grant-type:device_code"

  @spec start_device_flow(String.t() | nil) :: {:ok, map()} | {:error, term()}
  def start_device_flow(scope \\ "repo") do
    with {:ok, client_id} <- oauth_client_id(),
         {:ok, response} <-
           req_github()
           |> Req.post(
             url: @device_code_path,
             form: %{
               client_id: client_id,
               scope: scope || "repo"
             }
           ),
         {:ok, body} <- normalize_body(response) do
      {:ok, body}
    end
  end

  @spec poll_device_token(String.t()) :: {:ok, map()} | {:error, term()}
  def poll_device_token(device_code) when is_binary(device_code) do
    with {:ok, client_id} <- oauth_client_id(),
         {:ok, response} <-
           req_github()
           |> Req.post(
             url: @token_path,
             form: %{
               client_id: client_id,
               device_code: device_code,
               grant_type: @device_grant_type
             }
           ),
         {:ok, body} <- normalize_body(response) do
      case body do
        %{"access_token" => _token} -> {:ok, body}
        %{"error" => _error} -> {:error, {:oauth_error, body}}
        _ -> {:error, {:unexpected_oauth_response, body}}
      end
    end
  end

  def poll_device_token(_), do: {:error, :invalid_device_code}

  @spec fetch_user(String.t()) :: {:ok, map()} | {:error, term()}
  def fetch_user(access_token) when is_binary(access_token) do
    with {:ok, response} <-
           req_api(access_token)
           |> Req.get(url: @user_path),
         {:ok, body} <- normalize_body(response) do
      case body do
        %{"login" => _login} -> {:ok, body}
        _ -> {:error, {:unexpected_user_response, body}}
      end
    end
  end

  def fetch_user(_), do: {:error, :invalid_access_token}

  @spec oauth_client_id() :: {:ok, String.t()} | {:error, :oauth_client_id_missing}
  def oauth_client_id do
    case Application.get_env(:ide, Ide.GitHub, []) |> Keyword.get(:oauth_client_id) do
      id when is_binary(id) and id != "" -> {:ok, id}
      _ -> {:error, :oauth_client_id_missing}
    end
  end

  @spec req_github() :: Req.Request.t()
  defp req_github do
    Req.new(
      base_url: "https://github.com",
      headers: [
        {"accept", "application/json"},
        {"user-agent", "elm-pebble-ide"}
      ],
      receive_timeout: 15_000
    )
  end

  @spec req_api(String.t()) :: Req.Request.t()
  defp req_api(access_token) do
    Req.new(
      base_url: "https://api.github.com",
      headers: [
        {"accept", "application/vnd.github+json"},
        {"authorization", "Bearer #{access_token}"},
        {"x-github-api-version", "2022-11-28"},
        {"user-agent", "elm-pebble-ide"}
      ],
      receive_timeout: 15_000
    )
  end

  @spec normalize_body(term()) :: {:ok, map()} | {:error, term()}
  defp normalize_body(%Req.Response{status: status, body: body})
       when status in 200..299 and is_map(body),
       do: {:ok, body}

  defp normalize_body(%Req.Response{status: status, body: body}),
    do: {:error, {:http_error, status, body}}
end
