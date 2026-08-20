defmodule Ide.StoreListingUrls do
  @moduledoc """
  Default App Store listing URLs (website and source code) resolved from project settings.
  """

  alias Ide.AppStore.Types, as: AppStoreTypes
  alias Ide.GitHub.Credentials
  alias Ide.ProjectReadme
  alias Ide.Projects.Project
  alias Ide.Projects.Types, as: ProjectsTypes

  @type listing_url_project :: AppStoreTypes.publish_project()

  @default_source_repo "https://github.com/synalysis/elm-pebble"
  @app_page_base "https://apps.rePebble.com"

  @spec default_website_url() :: String.t()
  def default_website_url, do: ProjectReadme.site_url()

  @doc """
  Public Rebble App Store listing URL for a stored app id, or `nil` when unknown.
  """
  @spec app_page_url(listing_url_project() | String.t() | nil) :: String.t() | nil
  def app_page_url(project) when is_map(project) do
    app_page_url(Map.get(project, :store_app_id) || Map.get(project, "store_app_id"))
  end

  def app_page_url(store_app_id) when is_binary(store_app_id) do
    case String.trim(store_app_id) do
      "" -> nil
      id -> "#{@app_page_base}/#{id}"
    end
  end

  def app_page_url(_), do: nil

  @spec default_source_repo_url() :: String.t()
  def default_source_repo_url, do: @default_source_repo

  @doc """
  Website URL sent on App Store create (`website` field).
  Uses `release_defaults["website_url"]` when set, otherwise https://elm-pebble.dev.
  """
  @spec website_url(listing_url_project()) :: String.t()
  def website_url(project) when is_map(project) do
    project
    |> stored_url("website_url")
    |> case do
      "" -> default_website_url()
      url -> url
    end
  end

  @doc """
  Source code URL sent on App Store create (`source` field).
  Uses `release_defaults["source_url"]` when set; otherwise a public GitHub repo from project
  settings, otherwise https://github.com/synalysis/elm-pebble.
  """
  @spec source_url(listing_url_project()) :: String.t()
  def source_url(project) when is_map(project) do
    project
    |> stored_url("source_url")
    |> case do
      "" -> default_source_url(project)
      url -> url
    end
  end

  @spec default_source_url(listing_url_project()) :: String.t()
  def default_source_url(project) when is_map(project) do
    public_github_repo_url(project) || default_source_repo_url()
  end

  @doc """
  Placeholder for the Release “Source code URL” field.

  Uses the GitHub tab repository when that repo is known to exist; otherwise the
  generic elm-pebble default.
  """
  @spec source_url_placeholder(listing_url_project(), term()) :: String.t()
  def source_url_placeholder(project, repo_status \\ :idle)

  def source_url_placeholder(project, :exists) when is_map(project) do
    github_repo_url(project) || default_source_repo_url()
  end

  def source_url_placeholder(project, _repo_status) when is_map(project) do
    default_source_repo_url()
  end

  @doc """
  Returns `https://github.com/owner/repo` when owner (or the connected GitHub login)
  and repo name are set.
  """
  @spec github_repo_url(listing_url_project() | ProjectsTypes.github_config()) :: String.t() | nil
  def github_repo_url(%Project{} = project), do: github_repo_url(project.github || %{})

  def github_repo_url(project) when is_map(project) do
    github = github_config(project)
    owner = github_owner(github)
    repo = github |> Map.get("repo", "") |> to_string() |> String.trim()

    if owner != "" and repo != "" do
      "https://github.com/#{owner}/#{repo}"
    end
  end

  @doc """
  Returns `https://github.com/owner/repo` when GitHub visibility is public and owner/repo are set.
  """
  @spec public_github_repo_url(listing_url_project() | ProjectsTypes.github_config()) ::
          String.t() | nil
  def public_github_repo_url(%Project{} = project),
    do: public_github_repo_url(project.github || %{})

  def public_github_repo_url(project) when is_map(project) do
    github = github_config(project)
    visibility = github |> Map.get("visibility", "private") |> to_string()

    if visibility == "public" do
      github_repo_url(project)
    end
  end

  @spec form_website_url(listing_url_project()) :: String.t()
  def form_website_url(project) do
    case stored_url(project, "website_url") do
      "" -> default_website_url()
      url -> url
    end
  end

  @spec form_source_url(listing_url_project()) :: String.t()
  def form_source_url(project) do
    stored_url(project, "source_url")
  end

  @spec github_config(listing_url_project() | ProjectsTypes.github_config()) :: map()
  defp github_config(project) when is_map(project) do
    Map.get(project, :github) || Map.get(project, "github") ||
      if(github_map?(project), do: project, else: %{})
  end

  @spec github_map?(map()) :: boolean()
  defp github_map?(map) do
    Map.has_key?(map, "repo") or Map.has_key?(map, :repo) or
      Map.has_key?(map, "owner") or Map.has_key?(map, :owner)
  end

  @spec github_owner(map()) :: String.t()
  defp github_owner(github) when is_map(github) do
    case github
         |> Map.get("owner", Map.get(github, :owner, ""))
         |> to_string()
         |> String.trim() do
      "" ->
        case Credentials.current().user_login do
          login when is_binary(login) and login != "" -> login
          _ -> ""
        end

      owner ->
        owner
    end
  end

  @spec stored_url(listing_url_project(), String.t()) :: String.t()
  defp stored_url(project, key) when is_map(project) and is_binary(key) do
    project
    |> Map.get(:release_defaults, %{})
    |> case do
      defaults when is_map(defaults) -> Map.get(defaults, key, "")
      _ -> ""
    end
    |> to_string()
    |> String.trim()
  end
end
