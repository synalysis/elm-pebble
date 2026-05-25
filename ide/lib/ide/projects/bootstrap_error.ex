defmodule Ide.Projects.BootstrapError do
  @moduledoc false

  require Logger

  alias Ide.Paths
  alias Ide.Projects.Project

  @type operation :: :create | :import
  @type context :: %{
          optional(:operation) => operation(),
          optional(:template) => String.t(),
          optional(:source_path) => String.t(),
          optional(:workspace) => String.t()
        }

  @type bootstrap_reason ::
          atom()
          | File.posix()
          | tuple()
          | String.t()
          | map()

  @doc """
  Returns a user-facing explanation for a project bootstrap failure.
  """
  @spec describe(bootstrap_reason(), context()) :: String.t()
  def describe(reason, context \\ %{})

  def describe({:missing_template_asset, path}, _context) do
    """
    A required template file or directory is missing: #{path}

    #{priv_layout_hint(path)}
    """
    |> String.trim()
  end

  def describe({:unknown_template, template}, _context) do
    "Unknown project template #{inspect(template)}."
  end

  def describe(:import_source_not_found, %{source_path: path}) when is_binary(path) do
    "Import source directory not found: #{path}"
  end

  def describe(:import_source_not_found, _context) do
    "Import source directory not found."
  end

  def describe(:invalid_import_path, _context) do
    "Import path is invalid or escapes the project root."
  end

  def describe(:import_path_must_be_relative, _context) do
    "Import path must be relative to the import root."
  end

  def describe(:invalid_phone_elm_json, _context) do
    "Phone companion elm.json is invalid or unreadable."
  end

  def describe(:invalid_watch_elm_json, _context) do
    "Watch elm.json is invalid or unreadable."
  end

  def describe({:missing_union, detail}, _context) when is_binary(detail) do
    "Companion protocol generation failed: #{detail}"
  end

  def describe(:enoent, context) do
    """
    A required file or directory was not found during project bootstrap.

    #{maybe_workspace(context)}
    #{priv_layout_hint()}
    """
    |> String.trim()
  end

  def describe(:eacces, context) do
    """
    Permission denied while writing project files.

    #{maybe_workspace(context)}
    Check that PROJECTS_ROOT is writable by the IDE process.
    """
    |> String.trim()
  end

  def describe(:erofs, context) do
    """
    Project workspace is on a read-only filesystem.

    #{maybe_workspace(context)}
    """
    |> String.trim()
  end

  def describe(reason, context) do
    """
    Project bootstrap failed.

    #{maybe_workspace(context)}
    #{maybe_template(context)}
    Technical detail: #{inspect(reason)}
    """
    |> String.trim()
  end

  @doc """
  Logs a bootstrap failure with enough context to diagnose deployment issues.
  """
  @spec log_failure(operation(), Project.t(), bootstrap_reason(), context()) :: :ok
  def log_failure(operation, %Project{} = project, reason, context \\ %{}) do
    workspace = Map.get(context, :workspace) || workspace_for(project)
    context = Map.merge(context, %{operation: operation, workspace: workspace})

    Logger.error("""
    [Ide.Projects] #{operation_label(operation)} failed
    slug=#{project.slug}
    #{optional_line("template", Map.get(context, :template))}\
    #{optional_line("source_path", Map.get(context, :source_path))}\
    workspace=#{workspace}
    priv_dir=#{Paths.priv_dir() |> to_string()}
    reason=#{inspect(reason)}

    #{describe(reason, context)}
    """)

    :ok
  end

  @spec priv_layout_hint(String.t() | nil) :: String.t()
  defp priv_layout_hint(missing_path \\ nil) do
    priv = Paths.priv_dir() |> to_string()
    templates = Path.join(priv, "project_templates")
    bundled = Path.join(priv, "bundled_elm")

    templates_ok =
      File.dir?(templates) and
        case File.ls(templates) do
          {:ok, entries} when entries != [] -> true
          _ -> false
        end

    bundled_ok = File.dir?(bundled)

    cond do
      is_binary(missing_path) and String.contains?(missing_path, templates) and templates_ok ->
        """
        The project_templates tree exists under #{templates} but #{missing_path} is absent.
        Rebuild the IDE release/image so priv/project_templates is fully copied, or re-run mix compile in development after template changes.
        """

      templates_ok and bundled_ok ->
        "IDE template assets are present under #{priv}. If this error persists, check file permissions or disk space."

      not templates_ok and not bundled_ok ->
        """
        IDE template assets are missing under #{priv}.
        Expected directories:
          - #{templates}
          - #{bundled}
        For Docker/production releases, rebuild the image so priv/project_templates and priv/bundled_elm are included (see scripts/sync_bundled_elm.sh in the Dockerfile build).
        """

      not templates_ok ->
        """
        Project templates are missing under #{templates}.
        For Docker/production releases, rebuild the image so priv/project_templates is copied into the release.
        """

      true ->
        """
        Bundled Elm packages are missing under #{bundled}.
        For Docker/production releases, rebuild the image after running scripts/sync_bundled_elm.sh.
        """
    end
    |> String.trim()
  end

  @spec maybe_workspace(context()) :: String.t()
  defp maybe_workspace(%{workspace: workspace}) when is_binary(workspace),
    do: "Workspace: #{workspace}"

  defp maybe_workspace(_), do: ""

  @spec maybe_template(context()) :: String.t()
  defp maybe_template(%{template: template}) when is_binary(template),
    do: "Template: #{template}"

  defp maybe_template(_), do: ""

  @spec optional_line(String.t(), String.t() | nil) :: String.t()
  defp optional_line(_label, nil), do: ""
  defp optional_line(label, value), do: "#{label}=#{value}\n"

  @spec operation_label(operation()) :: String.t()
  defp operation_label(:create), do: "Project creation"
  defp operation_label(:import), do: "Project import"

  @spec workspace_for(Project.t()) :: String.t()
  defp workspace_for(%Project{owner_id: owner_id, slug: slug}) do
    root =
      Application.get_env(:ide, Ide.Projects, [])
      |> Keyword.get(:projects_root, Path.expand("workspace_projects"))

    if is_integer(owner_id) do
      Path.join([root, "users", Integer.to_string(owner_id), slug])
    else
      Path.join(root, slug)
    end
  end
end
