defmodule Ide.Auth do
  @moduledoc """
  Authentication helpers for local and public IDE modes.
  """

  import Ecto.Query

  alias Ide.Auth.User
  alias Ide.Repo

  @cloudpebble_firebase_api_key "AIzaSyBZ9Cdvwwv9At2lPmc8TxyyEqSXGXejGvc"
  @cloudpebble_firebase_project_id "coreapp-ce061"

  @type auth_mode :: :local | :public

  @spec mode() :: auth_mode()
  def mode do
    Application.get_env(:ide, __MODULE__, [])
    |> Keyword.get(:mode, :local)
    |> normalize_mode()
  end

  @spec public_mode?() :: boolean()
  def public_mode?, do: mode() == :public

  @spec firebase_config() :: map()
  def firebase_config do
    config = Application.get_env(:ide, __MODULE__, [])

    %{
      apiKey: Keyword.get(config, :firebase_api_key, @cloudpebble_firebase_api_key),
      authDomain: Keyword.get(config, :firebase_auth_domain, "coreapp-ce061.firebaseapp.com"),
      projectId: Keyword.get(config, :firebase_project_id, @cloudpebble_firebase_project_id),
      storageBucket:
        Keyword.get(config, :firebase_storage_bucket, "coreapp-ce061.firebasestorage.app"),
      messagingSenderId: Keyword.get(config, :firebase_messaging_sender_id, "460977838956"),
      appId: Keyword.get(config, :firebase_app_id, "1:460977838956:web:9a11a68ec78008fe303149")
    }
  end

  @spec get_user(integer() | nil) :: User.t() | nil
  def get_user(nil), do: nil
  def get_user(id), do: Repo.get(User, id)

  @spec upsert_firebase_user(map()) :: {:ok, User.t()} | {:error, term()}
  def upsert_firebase_user(%{"localId" => uid} = payload) when is_binary(uid) and uid != "" do
    attrs = %{
      firebase_uid: uid,
      email: payload["email"],
      display_name: payload["displayName"]
    }

    case Repo.get_by(User, firebase_uid: uid) do
      nil -> %User{}
      user -> user
    end
    |> User.changeset(attrs)
    |> Repo.insert_or_update()
  end

  def upsert_firebase_user(_payload), do: {:error, :missing_firebase_uid}

  @spec verify_firebase_id_token(String.t()) :: {:ok, map()} | {:error, term()}
  def verify_firebase_id_token(token) when is_binary(token) do
    token = String.trim(token)

    if token == "" do
      {:error, :missing_id_token}
    else
      api_key = firebase_config().apiKey
      url = "https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=#{URI.encode(api_key)}"

      case Req.post(url, json: %{idToken: token}, receive_timeout: 10_000) do
        {:ok, %{status: 200, body: %{"users" => [user | _]}}} when is_map(user) ->
          {:ok, user}

        {:ok, %{status: status, body: body}} ->
          {:error, {:firebase_lookup_failed, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def verify_firebase_id_token(_token), do: {:error, :missing_id_token}

  @spec token_exp(String.t()) :: integer() | nil
  def token_exp(token) when is_binary(token) do
    with [_header, payload, _sig] <- String.split(token, "."),
         {:ok, json} <- Base.url_decode64(payload, padding: false),
         {:ok, %{"exp" => exp}} <- Jason.decode(json),
         true <- is_integer(exp) do
      exp
    else
      _ -> nil
    end
  end

  def token_exp(_), do: nil

  @spec token_expired?(integer() | nil) :: boolean()
  def token_expired?(nil), do: false
  def token_expired?(exp), do: System.system_time(:second) >= exp

  @spec developer_status(String.t() | nil) :: {:ok, map()} | {:error, term()}
  def developer_status(token) when is_binary(token) and token != "" do
    base = appstore_api_base()

    case Req.get("#{base}/api/v1/developer/me",
           headers: [{"authorization", "Bearer #{token}"}],
           receive_timeout: 15_000
         ) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %{status: 403}} ->
        {:error, :not_developer}

      {:ok, %{status: status, body: body}} ->
        {:error, {:appstore_status_failed, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def developer_status(_token), do: {:error, :missing_id_token}

  @spec appstore_api_base() :: String.t()
  def appstore_api_base do
    Application.get_env(:ide, __MODULE__, [])
    |> Keyword.get(:appstore_api_base, "https://appstore-api.repebble.com")
    |> String.trim_trailing("/")
  end

  @spec preload_user_projects(User.t()) :: User.t()
  def preload_user_projects(%User{} = user), do: Repo.preload(user, :projects)

  @spec user_query() :: Ecto.Query.t()
  def user_query, do: from(u in User)

  defp normalize_mode(:public), do: :public
  defp normalize_mode("public"), do: :public
  defp normalize_mode(_), do: :local
end
