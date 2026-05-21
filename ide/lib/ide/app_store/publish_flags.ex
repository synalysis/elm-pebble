defmodule Ide.AppStore.PublishFlags do
  @moduledoc false

  alias Ide.Projects.Project

  @type visibility :: :published | :draft
  @type publish_flag_input :: boolean() | String.t() | integer() | nil

  @spec resolve_visibility(Project.t(), keyword()) :: visibility()
  def resolve_visibility(%Project{} = project, opts) do
    case Keyword.get(opts, :visibility) do
      :draft -> :draft
      :published -> :published
      "draft" -> :draft
      "published" -> :published
      _ -> visibility_from_publish_flags(project, opts)
    end
  end

  @spec resolve(Project.t(), keyword()) :: boolean()
  def resolve(project, opts) do
    project
    |> resolve_visibility(opts)
    |> published?()
  end

  @spec from_mcp_args(map()) :: boolean()
  def from_mcp_args(args) when is_map(args) do
    args
    |> visibility_from_mcp_args()
    |> published?()
  end

  @spec visibility_from_mcp_args(map()) :: visibility()
  def visibility_from_mcp_args(args) when is_map(args) do
    case Map.get(args, "is_published") do
      nil -> env_default_visibility()
      value -> visibility_from_flag(value)
    end
  end

  @spec published?(:published | :draft | publish_flag_input()) :: boolean()
  def published?(:published), do: true
  def published?(:draft), do: false
  def published?(value), do: visibility_from_flag(value) == :published

  @spec visibility_line(visibility()) :: String.t()
  def visibility_line(:published),
    do: "Release visibility: published (visible on the store listing)"

  def visibility_line(:draft),
    do:
      "Release visibility: draft (not public yet — enable “Make release visible immediately” or publish from the developer dashboard)"

  @spec api_is_published_string(visibility()) :: String.t()
  def api_is_published_string(:published), do: "true"
  def api_is_published_string(:draft), do: "false"

  @spec visibility_from_flag(publish_flag_input()) :: visibility()
  defp visibility_from_flag(value) do
    truthy?(value) && :published || :draft
  end

  @spec visibility_from_publish_flags(Project.t(), keyword()) :: visibility()
  defp visibility_from_publish_flags(%Project{} = project, opts) do
    case Keyword.fetch(opts, :is_published) do
      {:ok, value} -> visibility_from_flag(value)
      :error -> release_defaults_visibility(project.release_defaults)
    end
  end

  @spec release_defaults_visibility(map() | list() | nil) :: visibility()
  def release_defaults_visibility(defaults) when is_map(defaults) do
    case Map.get(defaults, "is_published") do
      nil ->
        case Map.get(defaults, :is_published) do
          nil -> env_default_visibility()
          value -> visibility_from_flag(value)
        end

      value ->
        visibility_from_flag(value)
    end
  end

  def release_defaults_visibility(_), do: env_default_visibility()

  @spec env_default_visibility() :: visibility()
  def env_default_visibility do
    case Application.get_env(:ide, Ide.AppStore.Publisher, []) do
      env when is_list(env) ->
        case Keyword.get(env, :publish_visible_by_default) do
          nil -> default_visibility()
          value -> visibility_from_flag(value)
        end

      _ ->
        default_visibility()
    end
  end

  @spec default_visibility() :: visibility()
  def default_visibility, do: :published

  @spec truthy?(publish_flag_input()) :: boolean()
  defp truthy?(value), do: value in [true, "true", 1, "1"]
end
