defmodule Ide.GitHub.Repositories do
  @moduledoc """
  GitHub repository lookup and creation for project settings.
  """

  alias Ide.GitHub.{Client, Credentials, Types}
  alias Ide.Projects.Project

  @type repo_status ::
          :idle
          | :checking
          | :unconfigured
          | :exists
          | :not_found
          | :forbidden
          | :error

  @valid_visibilities ~w(private public)

  @spec lookup_status(map(), keyword()) ::
          repo_status() | {:error, Types.connection_error() | Types.http_error()}
  def lookup_status(repo_config, opts \\ []) when is_map(repo_config) do
    with {:ok, repo} <- fetch_field(repo_config, "repo"),
         {:ok, token} <- fetch_token(),
         {:ok, resolved_owner} <- resolve_owner(config_owner(repo_config), opts) do
      case Client.fetch_repo(token, resolved_owner, repo, opts) do
        {:ok, _payload} -> :exists
        {:error, {:http_error, 404, _}} -> :not_found
        {:error, {:http_error, 403, _}} -> :forbidden
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :missing_field} -> :unconfigured
      {:error, :github_not_connected} -> {:error, :github_not_connected}
      {:error, :missing_github_user} -> {:error, :missing_github_user}
    end
  end

  @spec create_repository(Project.t(), Ide.Projects.Types.github_config(), keyword()) ::
          {:ok, map()} | {:error, Types.github_error()}
  def create_repository(%Project{} = project, repo_config, opts \\ []) when is_map(repo_config) do
    with {:ok, repo} <- fetch_field(repo_config, "repo"),
         :ok <- validate_repo_name(repo),
         {:ok, token} <- fetch_token(),
         {:ok, resolved_owner} <- resolve_owner(config_owner(repo_config), opts),
         {:ok, visibility} <- fetch_visibility(repo_config),
         params <- create_params(project, repo, visibility, opts),
         {:ok, payload} <- create_for_owner(token, resolved_owner, params, opts) do
      {:ok,
       %{
         owner: resolved_owner,
         repo: repo,
         html_url: payload["html_url"],
         private: payload["private"] == true
       }}
    end
  end

  @spec status_label(repo_status() | {:error, Types.github_error()}) :: String.t()
  def status_label(:idle), do: "Not checked yet"
  def status_label(:checking), do: "Checking…"
  def status_label(:unconfigured), do: "Set repository name (owner defaults to your GitHub user)"
  def status_label(:exists), do: "Repository exists on GitHub"
  def status_label(:not_found), do: "Repository not found on GitHub"
  def status_label(:forbidden), do: "No access (or repository is private to another account)"
  def status_label(:error), do: "Could not check repository status"

  def status_label({:error, :github_not_connected}),
    do: "Connect GitHub from IDE Settings first"

  def status_label({:error, :missing_github_user}),
    do: "Reconnect GitHub to refresh your account login"

  def status_label({:error, reason}), do: "Error: #{format_error(reason)}"

  @spec format_error(Types.github_error()) :: String.t()
  def format_error({:http_error, status, %{"message" => message}}),
    do: "GitHub API (#{status}): #{message}"

  def format_error({:http_error, status, body}) when is_map(body),
    do: "GitHub API (#{status}): #{inspect(body)}"

  def format_error({:http_error, status, body}),
    do: "GitHub API (#{status}): #{body}"

  def format_error({:invalid_repo_name, message}), do: message
  def format_error(:github_not_connected), do: "GitHub is not connected"
  def format_error(:missing_github_user), do: "GitHub user login is unavailable"
  def format_error({:missing_repo_field, field}), do: "Missing repository field: #{field}"
  def format_error(reason), do: inspect(reason)

  @spec config_owner(map()) :: String.t()
  defp config_owner(map) when is_map(map) do
    map
    |> Map.get("owner", Map.get(map, :owner, ""))
    |> to_string()
    |> String.trim()
  end

  @spec fetch_field(map(), String.t()) :: {:ok, String.t()} | {:error, :missing_field}
  defp fetch_field(map, key) when is_map(map) do
    value = Map.get(map, key) || Map.get(map, String.to_atom(key))

    case value do
      str when is_binary(str) ->
        trimmed = String.trim(str)
        if trimmed == "", do: {:error, :missing_field}, else: {:ok, trimmed}

      _ ->
        {:error, :missing_field}
    end
  end

  @spec fetch_token() :: {:ok, String.t()} | {:error, :github_not_connected}
  defp fetch_token do
    case Credentials.access_token() do
      token when is_binary(token) and token != "" -> {:ok, token}
      _ -> {:error, :github_not_connected}
    end
  end

  @spec resolve_owner(String.t(), keyword()) ::
          {:ok, String.t()} | {:error, :missing_github_user}
  defp resolve_owner(owner, opts) do
    owner = String.trim(owner)

    if owner != "" do
      {:ok, owner}
    else
      case Keyword.get(opts, :user_login) || Credentials.current().user_login do
        login when is_binary(login) and login != "" -> {:ok, login}
        _ -> {:error, :missing_github_user}
      end
    end
  end

  @spec fetch_visibility(map()) :: {:ok, String.t()}
  defp fetch_visibility(repo_config) do
    visibility =
      repo_config
      |> Map.get("visibility", Map.get(repo_config, :visibility, "private"))
      |> to_string()
      |> String.trim()
      |> String.downcase()

    if visibility in @valid_visibilities,
      do: {:ok, visibility},
      else: {:ok, "private"}
  end

  @spec validate_repo_name(String.t()) :: :ok | {:error, {:invalid_repo_name, String.t()}}
  defp validate_repo_name(name) do
    cond do
      String.match?(name, ~r/^[a-zA-Z0-9._-]+$/) ->
        :ok

      true ->
        {:error,
         {:invalid_repo_name,
          "Repository name may only contain letters, numbers, dots, hyphens, and underscores."}}
    end
  end

  @spec create_params(Project.t(), String.t(), String.t(), keyword()) :: map()
  defp create_params(%Project{} = project, repo, visibility, opts) do
    description =
      Keyword.get_lazy(opts, :description, fn ->
        defaults = project.release_defaults || %{}
        Map.get(defaults, "description", "") |> to_string() |> String.trim()
      end)

    %{
      "name" => repo,
      "private" => visibility == "private",
      "auto_init" => false
    }
    |> maybe_put_description(description)
  end

  @spec maybe_put_description(map(), String.t()) :: map()
  defp maybe_put_description(params, ""), do: params
  defp maybe_put_description(params, description), do: Map.put(params, "description", description)

  @spec create_for_owner(String.t(), String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  defp create_for_owner(token, owner, params, opts) do
    user_login = Keyword.get(opts, :user_login) || Credentials.current().user_login

    if is_binary(user_login) and owner == user_login do
      Client.create_user_repository(token, params, opts)
    else
      Client.create_org_repository(token, owner, params, opts)
    end
  end
end
