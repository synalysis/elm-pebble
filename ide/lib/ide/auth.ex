defmodule Ide.Auth do
  @moduledoc """
  Authentication helpers for local and public IDE modes.

  Modes:

  - `:local` — no login required for the IDE; App Store publish still uses Firebase on the Publish tab
  - `:public_pebble` — Firebase login (Rebble project) for IDE access and automated App Store publish
  - `:public_custom` — magic-link email login; publish offers PBW download instead of store submit
  """

  import Ecto.Query

  alias Ide.Auth.Email
  alias Ide.Auth.User
  alias Ide.Auth.Types, as: AuthTypes
  alias Ide.Projects
  alias Ide.Settings
  alias Ide.Repo

  @cloudpebble_firebase_api_key "AIzaSyBZ9Cdvwwv9At2lPmc8TxyyEqSXGXejGvc"
  @cloudpebble_firebase_project_id "coreapp-ce061"

  @type auth_mode :: :local | :public_pebble | :public_custom

  @spec mode() :: auth_mode()
  def mode do
    Application.get_env(:ide, __MODULE__, [])
    |> Keyword.get(:mode, :local)
    |> normalize_mode()
  end

  @doc """
  True when the IDE requires a logged-in user (`public_pebble` or `public_custom`).
  """
  @spec public_mode?() :: boolean()
  def public_mode?, do: mode() in [:public_pebble, :public_custom]

  @doc """
  True when Firebase + Rebble App Store automated publish are used.
  """
  @spec public_pebble_mode?() :: boolean()
  def public_pebble_mode?, do: mode() == :public_pebble

  @doc """
  True when users sign in with email magic links and publish via PBW download.
  """
  @spec public_custom_mode?() :: boolean()
  def public_custom_mode?, do: mode() == :public_custom

  @doc """
  True when remote MCP/ACP integration is available (local IDE deployments only).
  """
  @spec mcp_enabled?() :: boolean()
  def mcp_enabled?, do: not public_mode?()

  @doc """
  True when the IDE settings page should expose MCP/ACP and emulator setup controls.
  """
  @spec integration_settings_enabled?() :: boolean()
  def integration_settings_enabled?, do: mcp_enabled?()

  @doc """
  True when the IDE can submit releases to the Rebble App Store API.

  Enabled in local and public_pebble modes (Firebase login on the Publish tab).
  Disabled in public_custom (PBW download only).
  """
  @spec app_store_publish_enabled?() :: boolean()
  def app_store_publish_enabled?, do: mode() in [:local, :public_pebble]

  @spec firebase_config() :: AuthTypes.firebase_config()
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

  @spec send_login_link(String.t()) ::
          :ok
          | {:error, :invalid_email | :mailer_not_configured | :delivery_failed}
  def send_login_link(email), do: Email.send_login_link(email)

  @spec mail_delivery_configured?() :: boolean()
  def mail_delivery_configured?, do: Email.mail_delivery_configured?()

  @spec verify_login_token(String.t()) ::
          {:ok, User.t()} | {:error, :invalid_token | :expired_token | :used_token}
  def verify_login_token(token), do: Email.verify_login_token(token)

  @spec login_link_ttl_days() :: pos_integer()
  def login_link_ttl_days do
    Application.get_env(:ide, __MODULE__, [])
    |> Keyword.get(:login_link_ttl_days, 30)
  end

  @spec mail_from() :: {String.t(), String.t()}
  def mail_from do
    Application.get_env(:ide, __MODULE__, [])
    |> Keyword.get(:mail_from, {"elm-pebble IDE", "noreply@elm-pebble.dev"})
    |> normalize_mail_from()
  end

  defp normalize_mail_from({name, address}) when is_binary(name) and is_binary(address),
    do: {name, address}

  defp normalize_mail_from(address) when is_binary(address), do: {"elm-pebble IDE", address}
  defp normalize_mail_from(_), do: {"elm-pebble IDE", "noreply@elm-pebble.dev"}

  @spec upsert_firebase_user(AuthTypes.firebase_user()) ::
          {:ok, User.t()} | {:error, AuthTypes.firebase_user_error()}
  def upsert_firebase_user(%{"localId" => uid} = payload) when is_binary(uid) and uid != "" do
    attrs = %{
      firebase_uid: uid,
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

  @spec verify_firebase_id_token(String.t()) ::
          {:ok, AuthTypes.firebase_user()} | {:error, AuthTypes.firebase_token_error()}
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

  @spec developer_status(String.t() | nil) ::
          {:ok, AuthTypes.developer_profile()} | {:error, AuthTypes.developer_status_error()}
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

  @doc """
  Deletes a user's account, projects, login tokens, and on-disk workspace data.
  """
  @spec delete_user_data(User.t()) :: :ok | {:error, Ecto.Changeset.t()}
  def delete_user_data(%User{id: id} = user) when is_integer(id) do
    result =
      Repo.transaction(fn ->
        :ok = Projects.delete_all_for_user(%{id: id})

        case Repo.delete(user) do
          {:ok, _deleted} -> :ok
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)

    case result do
      {:ok, :ok} ->
        :ok = Settings.delete_user_settings(user)
        :ok

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @spec user_query() :: Ecto.Query.t()
  def user_query, do: from(u in User)

  defp normalize_mode(:public_pebble), do: :public_pebble
  defp normalize_mode(:public_custom), do: :public_custom
  defp normalize_mode(:public), do: :public_pebble
  defp normalize_mode("public_pebble"), do: :public_pebble
  defp normalize_mode("public_custom"), do: :public_custom
  defp normalize_mode("public"), do: :public_pebble
  defp normalize_mode(:local), do: :local
  defp normalize_mode("local"), do: :local
  defp normalize_mode(_), do: :local
end
