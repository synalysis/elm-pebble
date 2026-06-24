defmodule Ide.GitHub.Client do
  @moduledoc false

  alias Ide.GitHub.Types

  @device_code_path "/login/device/code"
  @token_path "/login/oauth/access_token"
  @user_path "/user"
  @device_grant_type "urn:ietf:params:oauth:grant-type:device_code"
  @oauth_scope "public_repo"

  @doc """
  OAuth scope requested during GitHub device authorization.

  Uses `public_repo` so the IDE can read and write public repositories only.
  """
  @spec oauth_scope() :: String.t()
  def oauth_scope, do: @oauth_scope

  @type http_method :: :get | :post
  @type mock_response ::
          {:ok, %{status: integer(), body: Types.http_body()}} | {:error, Types.api_error()}

  @spec start_device_flow(String.t() | nil) :: {:ok, Types.device_flow_payload()} | {:error, Types.api_error()}
  def start_device_flow(scope \\ @oauth_scope) do
    with {:ok, client_id} <- oauth_client_id(),
         {:ok, response} <-
           req_github()
           |> Req.post(
             url: @device_code_path,
             form: %{
               client_id: client_id,
               scope: scope || @oauth_scope
             }
           ),
         {:ok, body} <- normalize_body(response) do
      {:ok, body}
    end
  end

  @spec poll_device_token(String.t()) :: {:ok, Types.oauth_token_response()} | {:error, Types.auth_error()}
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

  @spec fetch_user(String.t()) :: {:ok, Types.user_profile()} | {:error, Types.auth_error()}
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

  @spec fetch_repo(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, Types.repository()} | {:error, Types.api_error()}
  def fetch_repo(access_token, owner, repo, opts \\ [])
      when is_binary(access_token) and is_binary(owner) and is_binary(repo) do
    owner = URI.encode(owner)
    repo = URI.encode(repo)

    api_request(access_token, opts, :get, "/repos/#{owner}/#{repo}", nil)
  end

  @spec create_user_repository(String.t(), Types.create_repo_params(), keyword()) ::
          {:ok, Types.repository()} | {:error, Types.api_error()}
  def create_user_repository(access_token, params, opts \\ []) when is_binary(access_token) do
    api_request(access_token, opts, :post, "/user/repos", params)
  end

  @spec create_org_repository(String.t(), String.t(), Types.create_repo_params(), keyword()) ::
          {:ok, Types.repository()} | {:error, Types.api_error()}
  def create_org_repository(access_token, org, params, opts \\ [])
      when is_binary(access_token) and is_binary(org) do
    org = URI.encode(org)

    api_request(access_token, opts, :post, "/orgs/#{org}/repos", params)
  end

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

  @spec req_api(String.t(), keyword()) :: Req.Request.t()
  defp req_api(access_token, _opts \\ []) do
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

  @spec api_request(String.t(), keyword(), http_method(), String.t(), Types.create_repo_params() | nil) ::
          {:ok, Types.api_json_response()} | {:error, Types.api_error()}
  defp api_request(access_token, opts, method, path, body) do
    headers = [
      {"accept", "application/vnd.github+json"},
      {"authorization", "Bearer #{access_token}"},
      {"x-github-api-version", "2022-11-28"},
      {"user-agent", "elm-pebble-ide"}
    ]

    case Keyword.get(opts, :request_fun) do
      fun when is_function(fun, 5) ->
        url = "https://api.github.com" <> path
        encoded = if is_map(body), do: Jason.encode!(body), else: body

        fun.(method, url, headers, encoded, 15_000)
        |> normalize_fun_response()

      _ ->
        request = req_api(access_token, opts)

        response =
          case {method, body} do
            {:get, _} -> Req.get(request, url: path)
            {:post, body} -> Req.post(request, url: path, json: body)
          end

        normalize_response(response)
    end
  end

  @spec normalize_fun_response(mock_response() | Types.req_transport_error()) ::
          {:ok, Types.api_json_response()}
          | {:error, Types.api_error()}
          | mock_response()
          | Types.req_transport_error()
  defp normalize_fun_response({:ok, %{status: status, body: body}})
       when status in 200..299 and is_map(body),
       do: {:ok, body}

  defp normalize_fun_response({:ok, %{status: status, body: body}}),
    do: {:error, {:http_error, status, body}}

  defp normalize_fun_response({:error, reason}), do: {:error, reason}

  defp normalize_fun_response(other), do: other

  @spec normalize_response({:ok, Req.Response.t()} | {:error, Types.req_transport_error()}) ::
          {:ok, Types.api_json_response()} | {:error, Types.api_error()}
  defp normalize_response({:ok, %Req.Response{} = response}), do: normalize_body(response)

  defp normalize_response({:error, reason}), do: {:error, reason}

  @spec normalize_body(Req.Response.t()) :: {:ok, Types.json_object()} | {:error, Types.http_error()}
  defp normalize_body(%Req.Response{status: status, body: body})
       when status in 200..299 and is_map(body),
       do: {:ok, body}

  defp normalize_body(%Req.Response{status: status, body: body}),
    do: {:error, {:http_error, status, body}}
end
