defmodule Ide.StoreListingUrls do
  @moduledoc """
  Default App Store listing URLs (website and source code) resolved from project settings.
  """

  alias Ide.ProjectReadme
  alias Ide.Projects.Project

  @default_source_repo "https://github.com/synalysis/elm-pebble"

  @spec default_website_url() :: String.t()
  def default_website_url, do: ProjectReadme.site_url()

  @spec default_source_repo_url() :: String.t()
  def default_source_repo_url, do: @default_source_repo

  @doc """
  Website URL sent on App Store create (`website` field).
  Uses `release_defaults["website_url"]` when set, otherwise https://elm-pebble.dev.
  """
  @spec website_url(map()) :: String.t()
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
  @spec source_url(map()) :: String.t()
  def source_url(project) when is_map(project) do
    project
    |> stored_url("source_url")
    |> case do
      "" -> default_source_url(project)
      url -> url
    end
  end

  @spec default_source_url(map()) :: String.t()
  def default_source_url(project) when is_map(project) do
    public_github_repo_url(project) || default_source_repo_url()
  end

  @doc """
  Returns `https://github.com/owner/repo` when GitHub visibility is public and owner/repo are set.
  """
  @spec public_github_repo_url(map()) :: String.t() | nil
  def public_github_repo_url(%Project{} = project),
    do: public_github_repo_url(project.github || %{})

  def public_github_repo_url(project) when is_map(project) do
    github = Map.get(project, :github) || Map.get(project, "github") || %{}

    owner = github |> Map.get("owner", "") |> to_string() |> String.trim()
    repo = github |> Map.get("repo", "") |> to_string() |> String.trim()
    visibility = github |> Map.get("visibility", "private") |> to_string()

    if visibility == "public" and owner != "" and repo != "" do
      "https://github.com/#{owner}/#{repo}"
    end
  end

  @spec form_website_url(map()) :: String.t()
  def form_website_url(project) do
    case stored_url(project, "website_url") do
      "" -> default_website_url()
      url -> url
    end
  end

  @spec form_source_url(map()) :: String.t()
  def form_source_url(project) do
    case stored_url(project, "source_url") do
      "" -> default_source_url(project)
      url -> url
    end
  end

  @spec stored_url(map(), String.t()) :: String.t()
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
