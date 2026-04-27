defmodule Ide.Projects do
  @moduledoc """
  IDE project persistence and workspace filesystem operations.
  """

  import Ecto.Query, warn: false

  alias Ide.Projects.FileStore
  alias Ide.Projects.Project
  alias Ide.AppStore
  alias Ide.Resources.ResourceStore
  alias Ide.ProjectBundle
  alias Ide.ProjectImport
  alias Ide.ProjectTemplates
  alias Ide.Repo

  @default_source_roots ["watch", "protocol", "phone"]

  @doc """
  Lists all projects.
  """
  @spec list_projects() :: term()
  def list_projects do
    Project
    |> order_by([p], asc: p.name)
    |> Repo.all()
  end

  @doc """
  Fetches a project by slug.
  """
  @spec get_project_by_slug(term()) :: term()
  def get_project_by_slug(slug), do: Repo.get_by(Project, slug: slug)

  @doc """
  Returns a project by id.
  """
  @spec get_project!(term()) :: term()
  def get_project!(id), do: Repo.get!(Project, id)

  @doc """
  Creates a project and bootstraps its source root directories.
  """
  @spec create_project(term()) :: term()
  def create_project(attrs) do
    attrs =
      attrs
      |> Map.new()
      |> infer_target_type_from_template()
      |> Map.put_new("source_roots", @default_source_roots)
      |> Map.put_new("template", "starter")

    Repo.transaction(fn ->
      with {:ok, project} <- %Project{} |> Project.changeset(attrs) |> Repo.insert(),
           :ok <- FileStore.ensure_roots(project, projects_root()),
           :ok <-
             ProjectTemplates.apply_template(template_key(attrs), project_workspace_path(project)),
           :ok <- ProjectBundle.write_manifest(project_workspace_path(project), project),
           :ok <- ensure_bitmap_generated(project) do
        maybe_activate_first(project)
        get_project!(project.id)
      else
        {:error, %Ecto.Changeset{} = changeset} -> Repo.rollback(changeset)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, project} -> {:ok, project}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Imports an existing project directory into IDE workspace roots.
  """
  @spec import_project(term(), term()) :: term()
  def import_project(attrs, import_path) do
    import_root = Path.expand(import_path)

    attrs =
      attrs
      |> Map.new()
      |> ProjectBundle.merge_attrs_from_manifest(import_root)
      |> Map.put_new("source_roots", @default_source_roots)

    Repo.transaction(fn ->
      with {:ok, source_path} <- ProjectBundle.resolve_import_source(import_root, attrs),
           project_attrs <- Map.drop(attrs, ["import_path"]),
           {:ok, project} <- %Project{} |> Project.changeset(project_attrs) |> Repo.insert(),
           :ok <- FileStore.ensure_roots(project, projects_root()),
           :ok <- ProjectImport.import(source_path, project_workspace_path(project)),
           :ok <- ProjectBundle.write_manifest(project_workspace_path(project), project),
           :ok <- ensure_bitmap_generated(project) do
        maybe_activate_first(project)
        get_project!(project.id)
      else
        {:error, %Ecto.Changeset{} = changeset} -> Repo.rollback(changeset)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, project} -> {:ok, project}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Exports a project workspace as a ZIP archive.
  """
  @spec export_project(term()) :: term()
  def export_project(%Project{} = project) do
    workspace_root = project_workspace_path(project)
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    zip_path = Path.join(System.tmp_dir!(), "#{project.slug}-#{timestamp}.zip")

    with :ok <- ProjectBundle.write_manifest(workspace_root, project),
         {:ok, entries} <- zip_entries(workspace_root),
         {:ok, _zip_file} <-
           :zip.create(String.to_charlist(zip_path), entries,
             cwd: String.to_charlist(workspace_root)
           ) do
      {:ok, zip_path}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Updates a project's metadata.
  """
  @spec update_project(term(), term()) :: term()
  def update_project(%Project{} = project, attrs) do
    with {:ok, updated} <-
           project
           |> Project.changeset(attrs)
           |> Repo.update(),
         :ok <- ProjectBundle.write_manifest(project_workspace_path(updated), updated) do
      {:ok, updated}
    end
  end

  @doc """
  Returns normalized GitHub repository config for a project.
  """
  @spec github_config(term()) :: map()
  def github_config(%Project{} = project) do
    config = project.github || %{}

    %{
      "owner" => Map.get(config, "owner", ""),
      "repo" => Map.get(config, "repo", ""),
      "branch" => Map.get(config, "branch", "main")
    }
  end

  @doc """
  Updates project GitHub repository config.
  """
  @spec update_github_config(term(), map()) :: term()
  def update_github_config(%Project{} = project, attrs) when is_map(attrs) do
    update_project(project, %{"github" => Map.new(attrs)})
  end

  @doc """
  Syncs app-level publish metadata from the public app store API.
  Requires `project.store_app_id`.
  """
  @spec sync_store_metadata(term(), term()) :: term()
  def sync_store_metadata(%Project{} = project, opts \\ []) do
    store_app_id =
      project.store_app_id
      |> to_string()
      |> String.trim()

    if store_app_id == "" do
      {:error, :store_app_id_required}
    else
      with {:ok, app} <- AppStore.fetch_app_by_id(store_app_id, opts) do
        attrs = %{
          "app_uuid" => app["uuid"] || project.app_uuid,
          "latest_published_version" =>
            get_in(app, ["latest_release", "version"]) || project.latest_published_version,
          "store_sync_at" => DateTime.utc_now(),
          "store_metadata_cache" => app
        }

        update_project(project, attrs)
      end
    end
  end

  @doc """
  Deletes a project and its local workspace.
  """
  @spec delete_project(term()) :: term()
  def delete_project(%Project{} = project) do
    workspace_path = FileStore.project_root(project, projects_root())

    case Repo.delete(project) do
      {:ok, deleted} ->
        _ = File.rm_rf(workspace_path)
        {:ok, deleted}

      other ->
        other
    end
  end

  @doc """
  Marks one project as active.
  """
  @spec activate_project(term()) :: term()
  def activate_project(%Project{} = project) do
    Repo.transaction(fn ->
      from(p in Project, where: p.active == true)
      |> Repo.update_all(set: [active: false])

      project
      |> Ecto.Changeset.change(active: true)
      |> Repo.update!()
    end)
    |> case do
      {:ok, active_project} -> {:ok, active_project}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Returns the active project when one is selected.
  """
  @spec active_project() :: term()
  def active_project do
    Repo.one(from p in Project, where: p.active == true, limit: 1)
  end

  @doc """
  Lists nested file tree nodes for each project source root.
  """
  @spec list_source_tree(term()) :: term()
  def list_source_tree(%Project{} = project) do
    FileStore.ensure_roots(project, projects_root())
    FileStore.list_tree(project, projects_root())
  end

  @doc """
  Reads file content from a source root.
  """
  @spec read_source_file(term(), term(), term()) :: term()
  def read_source_file(%Project{} = project, source_root, rel_path) do
    FileStore.read_file(project, projects_root(), source_root, rel_path)
  end

  @doc """
  Writes file content to a source root.
  """
  @spec write_source_file(term(), term(), term(), term()) :: term()
  def write_source_file(%Project{} = project, source_root, rel_path, contents) do
    FileStore.write_file(project, projects_root(), source_root, rel_path, contents)
  end

  @doc """
  Renames a file inside a source root.
  """
  @spec rename_source_path(term(), term(), term(), term()) :: term()
  def rename_source_path(%Project{} = project, source_root, old_rel_path, new_rel_path) do
    FileStore.rename_file(project, projects_root(), source_root, old_rel_path, new_rel_path)
  end

  @doc """
  Deletes a file or directory from a source root.
  """
  @spec delete_source_path(term(), term(), term()) :: term()
  def delete_source_path(%Project{} = project, source_root, rel_path) do
    FileStore.delete_path(project, projects_root(), source_root, rel_path)
  end

  @doc """
  Returns configured local workspace root for project files.
  """
  @spec projects_root() :: term()
  def projects_root do
    Application.get_env(:ide, Ide.Projects, [])
    |> Keyword.get(:projects_root, Path.expand("workspace_projects"))
  end

  @doc """
  Returns absolute workspace directory for a project slug.
  """
  @spec project_workspace_path(term()) :: term()
  def project_workspace_path(%Project{} = project) do
    FileStore.project_root(project, projects_root())
  end

  @doc """
  Lists bitmap resources for a project.
  """
  @spec list_bitmap_resources(term()) :: term()
  def list_bitmap_resources(%Project{} = project) do
    ResourceStore.list(project)
  end

  @doc """
  Imports a bitmap resource and regenerates the generated resources Elm module.
  """
  @spec import_bitmap_resource(term(), term(), term()) :: term()
  def import_bitmap_resource(%Project{} = project, upload_path, original_name) do
    ResourceStore.import_bitmap(project, upload_path, original_name)
  end

  @doc """
  Deletes one bitmap resource and regenerates the generated resources Elm module.
  """
  @spec delete_bitmap_resource(term(), term()) :: term()
  def delete_bitmap_resource(%Project{} = project, ctor) do
    ResourceStore.delete_bitmap(project, ctor)
  end

  @doc """
  Ensures the generated resources module exists and is up to date.
  """
  @spec ensure_bitmap_generated(term()) :: term()
  def ensure_bitmap_generated(%Project{} = project) do
    ResourceStore.ensure_generated(project)
  end

  @doc """
  Lists font resources for a project.
  """
  @spec list_font_resources(term()) :: term()
  def list_font_resources(%Project{} = project) do
    ResourceStore.list_fonts(project)
  end

  @doc """
  Imports a font resource and regenerates the generated resources Elm module.
  """
  @spec import_font_resource(term(), term(), term()) :: term()
  def import_font_resource(%Project{} = project, upload_path, original_name) do
    ResourceStore.import_font(project, upload_path, original_name)
  end

  @doc """
  Deletes one font resource and regenerates the generated resources Elm module.
  """
  @spec delete_font_resource(term(), term()) :: term()
  def delete_font_resource(%Project{} = project, ctor) do
    ResourceStore.delete_font(project, ctor)
  end

  @spec maybe_activate_first(term()) :: term()
  defp maybe_activate_first(project) do
    if is_nil(active_project()) do
      activate_project(project)
    else
      :ok
    end
  end

  @spec template_key(term()) :: term()
  defp template_key(attrs), do: Map.get(attrs, "template", "starter")

  @spec infer_target_type_from_template(term()) :: term()
  defp infer_target_type_from_template(attrs) do
    template = Map.get(attrs, "template", "starter")
    Map.put(attrs, "target_type", Ide.ProjectTemplates.target_type_for_template(template))
  end

  @spec zip_entries(term()) :: term()
  defp zip_entries(workspace_root) do
    entries =
      workspace_root
      |> Path.join("**/*")
      |> Path.wildcard(match_dot: true)
      |> Enum.reject(&File.dir?/1)
      |> Enum.map(&Path.relative_to(&1, workspace_root))
      |> Enum.reject(&inside_hidden_directory?/1)
      |> Enum.map(&String.to_charlist/1)

    {:ok, entries}
  rescue
    error -> {:error, error}
  end

  @spec inside_hidden_directory?(term()) :: term()
  defp inside_hidden_directory?(relative_path) do
    relative_path
    |> Path.dirname()
    |> case do
      "." ->
        false

      dirname ->
        dirname
        |> String.split("/", trim: true)
        |> Enum.any?(&String.starts_with?(&1, "."))
    end
  end
end
