defmodule Ide.Projects do
  @moduledoc """
  IDE project persistence and workspace filesystem operations.
  """

  import Ecto.Query, warn: false

  alias Ide.Projects.FileStore
  alias Ide.Projects.FileTypes
  alias Ide.Projects.Project
  alias Ide.Projects.Types
  alias Ide.AppStore
  alias Ide.Debugger
  alias Ide.Resources.ResourceStore
  alias Ide.ProjectBundle
  alias Ide.PebbleToolchain
  alias Ide.GitHub.Clone, as: GitHubClone
  alias Ide.ProjectImport
  alias Ide.ProjectTemplates
  alias Ide.PebblePreferences
  alias Ide.Repo

  @default_source_roots ["watch", "protocol", "phone"]

  @doc """
  Lists all projects.
  """
  @spec list_projects(Types.scope_user()) :: [Project.t()]
  def list_projects(user \\ :current_scope) do
    user = current_scope_user(user)

    Project
    |> scope_to_user(user)
    |> order_by([p], asc: p.name)
    |> Repo.all()
  end

  @doc """
  Fetches a project by slug.
  """
  @spec get_project_by_slug(String.t(), Types.scope_user()) :: Project.t() | nil
  def get_project_by_slug(slug, user \\ :current_scope) do
    user = current_scope_user(user)

    Project
    |> scope_to_user(user)
    |> Repo.get_by(slug: slug)
  end

  @doc """
  Returns a project by id.
  """
  @spec get_project!(integer() | String.t(), Types.scope_user() | :any) :: Project.t()
  def get_project!(id, user \\ :any)

  def get_project!(id, :any), do: Repo.get!(Project, id)

  def get_project!(id, user) do
    Project
    |> scope_to_user(user)
    |> Repo.get!(id)
  end

  @doc """
  Creates a project and bootstraps its source root directories.
  """
  @spec create_project(Types.project_attrs(), Types.scope_user()) :: Types.create_result()
  def create_project(attrs, user \\ nil) do
    attrs =
      attrs
      |> Map.new()
      |> put_owner(user)
      |> infer_target_type_from_template()
      |> merge_template_release_defaults()
      |> Map.put_new("source_roots", @default_source_roots)
      |> Map.put_new("template", "starter")
      |> assign_default_app_uuid()

    Repo.transaction(fn ->
      with {:ok, project} <- %Project{} |> Project.changeset(attrs) |> Repo.insert(),
           :ok <- FileStore.ensure_roots(project, projects_root()),
           :ok <-
             ProjectTemplates.apply_template(template_key(attrs), project_workspace_path(project)),
           :ok <- Ide.ProjectReadme.write(project_workspace_path(project), project),
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
      {:ok, project} -> ensure_app_uuid(project)
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Imports an existing project directory into IDE workspace roots.
  """
  @spec import_project(Types.project_attrs(), String.t(), Types.scope_user()) ::
          Types.create_result()
  def import_project(attrs, import_path, user \\ nil) do
    import_root = Path.expand(import_path)

    attrs =
      attrs
      |> Map.new()
      |> put_owner(user)
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
      {:ok, project} -> ensure_app_uuid(project)
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Clones a GitHub repository and imports it as an IDE project workspace.
  """
  @spec import_from_github(map(), map(), Types.scope_user(), keyword()) ::
          {:ok, Project.t()} | {:error, Types.project_error()}
  def import_from_github(attrs, github_params, user \\ nil, opts \\ []) do
    with {:ok, repo_ref} <- resolve_github_repo_ref(github_params),
         {:ok, clone_path} <- clone_path_for_import(repo_ref, opts) do
      try do
        attrs
        |> attrs_for_github_import(clone_path, repo_ref)
        |> then(&import_project(&1, clone_path, user))
      after
        File.rm_rf(clone_path)
      end
    end
  end

  @spec clone_path_for_import(map(), keyword()) :: {:ok, String.t()} | {:error, Types.project_error()}
  defp clone_path_for_import(repo_ref, opts) do
    case Keyword.get(opts, :clone_path) do
      path when is_binary(path) -> {:ok, path}
      _ -> GitHubClone.clone(repo_ref.owner, repo_ref.repo, repo_ref.branch, opts)
    end
  end

  @spec resolve_github_repo_ref(map()) :: {:ok, map()} | {:error, Types.project_error()}
  defp resolve_github_repo_ref(params) when is_map(params) do
    owner = params |> Map.get("owner", Map.get(params, :owner, "")) |> to_string() |> String.trim()
    repo = params |> Map.get("repo", Map.get(params, :repo, "")) |> to_string() |> String.trim()
    branch = params |> Map.get("branch", Map.get(params, :branch, "main")) |> to_string() |> String.trim()

    repo_url =
      params
      |> Map.get("repo_url", Map.get(params, :repo_url, ""))
      |> to_string()
      |> String.trim()

    cond do
      owner != "" and repo != "" ->
        {:ok, %{owner: owner, repo: repo, branch: if(branch == "", do: "main", else: branch)}}

      repo_url != "" ->
        case GitHubClone.parse_repo_ref(repo_url) do
          {:ok, parsed} ->
            branch =
              if branch != "" and branch != "main",
                do: branch,
                else: Map.get(parsed, :branch, "main")

            {:ok, Map.put(parsed, :branch, branch)}

          error ->
            error
        end

      true ->
        {:error, :missing_github_repo}
    end
  end

  @spec attrs_for_github_import(map(), String.t(), map()) :: map()
  defp attrs_for_github_import(attrs, clone_path, %{owner: owner, repo: repo, branch: branch}) do
    attrs =
      attrs
      |> Map.new()
      |> ProjectBundle.merge_attrs_from_manifest(clone_path)

    name = Map.get(attrs, "name", "") |> to_string() |> String.trim()
    slug = Map.get(attrs, "slug", "") |> to_string() |> String.trim()

    attrs =
      attrs
      |> maybe_put("name", name, humanize_repo_name(repo))
      |> maybe_put("slug", slug, slugify_repo(repo))
      |> Map.put_new("target_type", infer_target_type(clone_path))
      |> Map.put_new("source_roots", @default_source_roots)
      |> Map.put("github", %{
        "owner" => owner,
        "repo" => repo,
        "branch" => branch,
        "visibility" => "private"
      })

    attrs
  end

  @spec maybe_put(map(), String.t(), String.t(), String.t()) :: map()
  defp maybe_put(attrs, key, "", fallback), do: Map.put(attrs, key, fallback)
  defp maybe_put(attrs, key, value, _fallback) when value != "", do: Map.put(attrs, key, value)

  @spec humanize_repo_name(String.t()) :: String.t()
  defp humanize_repo_name(repo) do
    repo
    |> String.replace("-", " ")
    |> String.replace("_", " ")
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  @spec slugify_repo(String.t()) :: String.t()
  defp slugify_repo(repo) do
    repo
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  @spec infer_target_type(String.t()) :: String.t()
  defp infer_target_type(clone_path) do
    case ProjectBundle.read_manifest(clone_path) do
      {:ok, metadata} -> metadata.target_type
      {:error, _} -> if(File.dir?(Path.join(clone_path, "phone")), do: "app", else: "watchface")
    end
  end

  @doc """
  Exports a project workspace as a ZIP archive.
  """
  @spec export_project(Project.t()) :: {:ok, String.t()} | {:error, Types.project_error()}
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
  Persists a Pebble app UUID on the project and in `elm-pebble.project.json`.
  """
  @spec persist_app_uuid(Project.t(), String.t()) :: {:ok, Project.t()} | {:error, Types.project_error()}
  def persist_app_uuid(%Project{} = project, uuid) when is_binary(uuid) do
    case normalize_app_uuid(uuid) do
      nil -> {:ok, project}
      normalized -> update_project(project, %{"app_uuid" => normalized})
    end
  end

  @doc """
  Ensures the project and manifest have a Pebble app UUID when one can be resolved.
  """
  @spec ensure_app_uuid(Project.t()) :: {:ok, Project.t()} | {:error, Types.project_error()}
  def ensure_app_uuid(%Project{} = project) do
    workspace = project_workspace_path(project)
    current = normalize_app_uuid(project.app_uuid)

    resolved =
      current ||
        ProjectBundle.resolve_app_uuid(workspace, project.slug)

    case resolved do
      nil -> {:ok, project}
      ^current -> {:ok, project}
      uuid -> update_project(project, %{"app_uuid" => uuid})
    end
  end

  @doc """
  Updates a project's metadata.
  """
  @spec update_project(Project.t(), Types.project_attrs()) :: Types.update_result()
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
  @spec github_config(Project.t()) :: Types.github_config()
  def github_config(%Project{} = project) do
    config = project.github || %{}

    %{
      "owner" => Map.get(config, "owner", ""),
      "repo" => Map.get(config, "repo", ""),
      "branch" => Map.get(config, "branch", "main"),
      "visibility" => github_visibility(Map.get(config, "visibility", "private"))
    }
  end

  @spec github_visibility(String.t() | atom() | nil) :: String.t()
  def github_visibility(value) when value in ["private", "public"], do: value

  def github_visibility(value) when is_atom(value) do
    value |> Atom.to_string() |> github_visibility()
  end

  def github_visibility(_), do: "private"

  @doc """
  Updates project GitHub repository config.
  """
  @spec update_github_config(Project.t(), Types.github_config()) :: Types.update_result()
  def update_github_config(%Project{} = project, attrs) when is_map(attrs) do
    update_project(project, %{"github" => Map.new(attrs)})
  end

  @doc """
  Syncs app-level publish metadata from the public app store API.
  Requires `project.store_app_id`.
  """
  @spec sync_store_metadata(Project.t(), keyword()) :: Types.update_result() | {:error, atom()}
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
  @spec delete_project(Project.t()) :: {:ok, Project.t()} | {:error, Ecto.Changeset.t()}
  def delete_project(%Project{} = project) do
    workspace_path = FileStore.project_root(project, projects_root())

    case Repo.delete(project) do
      {:ok, deleted} ->
        :ok = Debugger.forget_project(project.slug)
        _ = File.rm_rf(workspace_path)
        {:ok, deleted}

      other ->
        other
    end
  end

  @doc """
  Marks one project as active.
  """
  @spec activate_project(Project.t()) :: {:ok, Project.t()} | {:error, Types.project_error()}
  def activate_project(%Project{} = project) do
    Repo.transaction(fn ->
      active_scope_for(project)
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
  @spec active_project(Types.scope_user()) :: Project.t() | nil
  def active_project(user \\ nil) do
    Project
    |> scope_to_user(user)
    |> where([p], p.active == true)
    |> limit(1)
    |> Repo.one()
  end

  @spec scope_to_user(Ecto.Queryable.t(), Types.scope_user()) :: Ecto.Query.t()
  def scope_to_user(queryable, nil), do: from(p in queryable, where: is_nil(p.owner_id))
  def scope_to_user(queryable, %{id: nil}), do: scope_to_user(queryable, nil)
  def scope_to_user(queryable, %{id: id}), do: from(p in queryable, where: p.owner_id == ^id)

  defp put_owner(attrs, nil), do: attrs
  defp put_owner(attrs, %{id: id}) when is_integer(id), do: Map.put(attrs, "owner_id", id)

  defp current_scope_user(:current_scope), do: Process.get(:ide_current_user)
  defp current_scope_user(user), do: user

  @doc """
  Lists nested file tree nodes for each project source root.
  """
  @spec list_source_tree(Project.t()) :: Types.source_tree()
  def list_source_tree(%Project{} = project) do
    FileStore.ensure_roots(project, projects_root())
    ensure_generated_phone_preferences(project)
    ensure_protocol_for_phone_companion(project)
    FileStore.list_tree(project, projects_root())
  end

  @doc """
  Reads file content from a source root.
  """
  @spec read_source_file(Project.t(), String.t(), String.t()) :: Types.read_result()
  def read_source_file(%Project{} = project, source_root, rel_path) do
    FileStore.read_file(project, projects_root(), source_root, rel_path)
  end

  @doc """
  Writes file content to a source root.
  """
  @spec write_source_file(Project.t(), String.t(), String.t(), iodata()) :: Types.write_result()
  def write_source_file(%Project{} = project, source_root, rel_path, contents) do
    case FileStore.write_file(project, projects_root(), source_root, rel_path, contents) do
      :ok = ok ->
        if capability_sync_source?(source_root, rel_path) do
          _ = sync_detected_capabilities(project)
        end

        ok

      other ->
        other
    end
  end

  @doc """
  Merges Pebble capabilities inferred from Elm source usage into project settings.

  Existing capabilities are preserved; newly detected ones are added automatically.
  """
  @spec sync_detected_capabilities(Project.t()) :: {:ok, Project.t()} | {:error, Types.project_error()}
  def sync_detected_capabilities(%Project{} = project) do
    workspace_root = project_workspace_path(project)
    detected = Ide.ProjectCapabilities.infer_workspace(workspace_root)

    current =
      project
      |> Map.get(:release_defaults, %{})
      |> Map.get("capabilities", [])
      |> IdeWeb.WorkspaceLive.State.capabilities_form_value()
      |> MapSet.new()

    merged = MapSet.union(current, detected)

    if MapSet.equal?(merged, current) do
      {:ok, project}
    else
      defaults = Map.put(project.release_defaults || %{}, "capabilities", MapSet.to_list(merged))

      update_project(project, %{"release_defaults" => defaults})
    end
  end

  @spec capability_sync_source?(String.t(), String.t()) :: boolean()
  defp capability_sync_source?(source_root, rel_path)
       when is_binary(source_root) and is_binary(rel_path) do
    source_root in ["watch", "phone"] and String.ends_with?(rel_path, ".elm")
  end

  defp capability_sync_source?(_, _), do: false

  @doc """
  Adds the default companion app and protocol scaffolding to a watch-only project.
  """
  @spec add_companion_app(Project.t()) :: :ok | {:error, Types.project_error()}
  def add_companion_app(%Project{} = project) do
    ProjectTemplates.ensure_companion_app(project_workspace_path(project))
  end

  @doc """
  Returns true when the project has a companion app entrypoint.
  """
  @spec companion_app_present?(Project.t()) :: boolean()
  def companion_app_present?(%Project{} = project) do
    workspace_root = project_workspace_path(project)

    File.exists?(Path.join(workspace_root, "phone/src/CompanionApp.elm"))
  end

  @doc """
  Renames a file inside a source root.
  """
  @spec rename_source_path(Project.t(), String.t(), String.t(), String.t()) ::
          FileTypes.rename_result()
  def rename_source_path(%Project{} = project, source_root, old_rel_path, new_rel_path) do
    FileStore.rename_file(project, projects_root(), source_root, old_rel_path, new_rel_path)
  end

  @doc """
  Deletes a file or directory from a source root.
  """
  @spec delete_source_path(Project.t(), String.t(), String.t()) :: FileTypes.delete_result()
  def delete_source_path(%Project{} = project, source_root, rel_path) do
    FileStore.delete_path(project, projects_root(), source_root, rel_path)
  end

  @doc """
  Returns configured local workspace root for project files.
  """
  @spec projects_root() :: FileTypes.projects_root()
  def projects_root do
    Application.get_env(:ide, Ide.Projects, [])
    |> Keyword.get(:projects_root, Path.expand("workspace_projects"))
  end

  @doc """
  Returns absolute workspace directory for a project slug.
  """
  @spec project_workspace_path(Project.t() | String.t()) :: String.t()
  def project_workspace_path(%Project{} = project) do
    FileStore.project_root(project, projects_root())
  end

  @doc """
  Returns the newest prepared `.pbw` in the project workspace, if any.
  """
  @spec latest_pbw_path(Project.t()) :: {:ok, String.t()} | {:error, :pbw_not_found}
  def latest_pbw_path(%Project{} = project) do
    case ProjectBundle.workspace_latest_pbw_path(project_workspace_path(project)) do
      path when is_binary(path) -> {:ok, path}
      _ -> {:error, :pbw_not_found}
    end
  end

  @doc """
  Download filename for a prepared PBW: `<slug>-<version>.pbw`.
  """
  @spec pbw_download_filename(Project.t()) :: String.t()
  def pbw_download_filename(%Project{} = project) do
    slug = pbw_filename_segment(project.slug)
    version = pbw_release_version(project)
    "#{slug}-#{version}.pbw"
  end

  @spec pbw_release_version(Project.t()) :: String.t()
  defp pbw_release_version(%Project{} = project) do
    defaults = project.release_defaults || %{}

    defaults
    |> Map.get("version_label", "")
    |> blank_to_nil()
    |> case do
      nil ->
        package_json_version(project_workspace_path(project)) ||
          blank_to_nil(project.latest_published_version) ||
          "0.0.0"

      version ->
        version
    end
    |> pbw_filename_segment()
  end

  @spec package_json_version(String.t()) :: String.t() | nil
  defp package_json_version(workspace_root) do
    path = Path.join(workspace_root, ".pebble-sdk/app/package.json")

    with {:ok, source} <- File.read(path),
         {:ok, %{"version" => version}} <- Jason.decode(source) do
      version |> to_string() |> String.trim() |> blank_to_nil()
    else
      _ -> nil
    end
  end

  @spec pbw_filename_segment(String.t()) :: String.t()
  defp pbw_filename_segment(value) do
    value
    |> to_string()
    |> String.trim()
    |> String.replace(~r/[^a-zA-Z0-9._-]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "unknown"
      segment -> segment
    end
  end

  @spec blank_to_nil(String.t()) :: String.t() | nil
  defp blank_to_nil(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: String.trim(value)
  end

  defp blank_to_nil(_), do: nil

  @doc """
  Directory for emulator screenshots inside the project workspace (outside `.pebble-sdk`).
  """
  @spec screenshots_path(Project.t()) :: String.t()
  def screenshots_path(%Project{} = project) do
    Path.join(project_workspace_path(project), "screenshots")
  end

  @doc """
  Lists bitmap resources for a project.
  """
  @spec list_bitmap_resources(Project.t()) ::
          {:ok, [ResourceStore.bitmap_entry()]} | {:error, Types.project_error()}
  def list_bitmap_resources(%Project{} = project) do
    ResourceStore.list(project)
  end

  @doc """
  Imports a bitmap resource and regenerates the generated resources Elm module.
  """
  @spec import_bitmap_resource(Project.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Types.project_error()}
  def import_bitmap_resource(%Project{} = project, upload_path, original_name) do
    ResourceStore.import_bitmap(project, upload_path, original_name)
  end

  @doc """
  Deletes one bitmap resource and regenerates the generated resources Elm module.
  """
  @spec delete_bitmap_resource(Project.t(), String.t()) :: {:ok, [map()]} | {:error, Types.project_error()}
  def delete_bitmap_resource(%Project{} = project, ctor) do
    ResourceStore.delete_bitmap(project, ctor)
  end

  @doc """
  Ensures the generated resources module exists and is up to date.
  """
  @spec ensure_bitmap_generated(Project.t()) :: :ok | {:error, Types.project_error()}
  def ensure_bitmap_generated(%Project{} = project) do
    ResourceStore.ensure_generated(project)
  end

  @doc """
  Ensures the generated phone preferences bridge exists when a phone app declares preferences.
  """
  @spec ensure_generated_phone_preferences(Project.t()) :: :ok
  def ensure_generated_phone_preferences(%Project{} = project) do
    phone_root = Path.join(project_workspace_path(project), "phone")

    if File.exists?(Path.join(phone_root, "elm.json")) do
      _ = PebblePreferences.ensure_generated_bridge(phone_root)
    end

    :ok
  end

  @doc """
  Ensures projects with a companion app also have the default protocol contract root.
  """
  @spec ensure_protocol_for_phone_companion(Project.t()) :: :ok
  def ensure_protocol_for_phone_companion(%Project{} = project) do
    workspace_root = project_workspace_path(project)
    phone_root = Path.join(workspace_root, "phone")

    if File.exists?(Path.join(phone_root, "elm.json")) do
      _ = ProjectTemplates.ensure_protocol_shared(workspace_root)
      _ = ProjectTemplates.ensure_phone_companion_source_dirs(workspace_root)
    end

    :ok
  end

  @doc """
  Lists font resources for a project.
  """
  @spec list_font_resources(Project.t()) ::
          {:ok, [ResourceStore.font_entry()]} | {:error, Types.project_error()}
  def list_font_resources(%Project{} = project) do
    ResourceStore.list_fonts(project)
  end

  @doc """
  Lists uploaded source font files for a project.
  """
  @spec list_font_sources(Project.t()) ::
          {:ok, [ResourceStore.font_source()]} | {:error, Types.project_error()}
  def list_font_sources(%Project{} = project) do
    ResourceStore.list_font_sources(project)
  end

  @doc """
  Imports a font resource and regenerates the generated resources Elm module.
  """
  @spec import_font_resource(Project.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Types.project_error()}
  def import_font_resource(%Project{} = project, upload_path, original_name) do
    ResourceStore.import_font(project, upload_path, original_name)
  end

  @doc """
  Adds a generated font variant for an uploaded source font.
  """
  @spec add_font_variant(Project.t(), map()) :: {:ok, map()} | {:error, Types.project_error()}
  def add_font_variant(%Project{} = project, params) when is_map(params) do
    ResourceStore.add_font_variant(project, params)
  end

  @doc """
  Updates a generated font variant.
  """
  @spec update_font_variant(Project.t(), String.t(), map()) ::
          {:ok, map()} | {:error, Types.project_error()}
  def update_font_variant(%Project{} = project, ctor, params)
      when is_binary(ctor) and is_map(params) do
    ResourceStore.update_font_variant(project, ctor, params)
  end

  @doc """
  Deletes one font resource and regenerates the generated resources Elm module.
  """
  @spec delete_font_resource(Project.t(), String.t()) :: {:ok, [map()]} | {:error, Types.project_error()}
  def delete_font_resource(%Project{} = project, ctor) do
    ResourceStore.delete_font(project, ctor)
  end

  @doc """
  Deletes an uploaded source font and its generated variants.
  """
  @spec delete_font_source(Project.t(), String.t()) :: {:ok, map()} | {:error, Types.project_error()}
  def delete_font_source(%Project{} = project, source_id) when is_binary(source_id) do
    ResourceStore.delete_font_source(project, source_id)
  end

  @spec maybe_activate_first(Project.t()) :: :ok | {:ok, Project.t()} | {:error, Types.project_error()}
  defp maybe_activate_first(project) do
    if is_nil(active_project(%{id: project.owner_id})) do
      activate_project(project)
    else
      :ok
    end
  end

  defp active_scope_for(%Project{owner_id: nil}) do
    from(p in Project, where: p.active == true and is_nil(p.owner_id))
  end

  defp active_scope_for(%Project{owner_id: owner_id}) do
    from(p in Project, where: p.active == true and p.owner_id == ^owner_id)
  end

  @spec template_key(map()) :: String.t()
  defp template_key(attrs), do: Map.get(attrs, "template", "starter")

  @spec infer_target_type_from_template(map()) :: map()
  defp infer_target_type_from_template(attrs) do
    template = Map.get(attrs, "template", "starter")
    Map.put(attrs, "target_type", Ide.ProjectTemplates.target_type_for_template(template))
  end

  @spec merge_template_release_defaults(map()) :: map()
  defp merge_template_release_defaults(attrs) do
    template = Map.get(attrs, "template", "starter")
    template_defaults = Ide.ProjectTemplates.default_release_defaults(template)

    release_defaults =
      attrs
      |> Map.get("release_defaults", %{})
      |> case do
        defaults when is_map(defaults) -> defaults
        _ -> %{}
      end

    Map.put(attrs, "release_defaults", Map.merge(template_defaults, release_defaults))
  end

  @spec zip_entries(String.t()) :: {:ok, [charlist()]} | {:error, Types.project_error()}
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

  @spec assign_default_app_uuid(map()) :: map()
  defp assign_default_app_uuid(attrs) do
    case normalize_app_uuid(Map.get(attrs, "app_uuid")) do
      nil ->
        slug = attrs |> Map.get("slug") |> to_string() |> String.trim()

        if slug != "" do
          Map.put(attrs, "app_uuid", PebbleToolchain.deterministic_app_uuid(slug))
        else
          attrs
        end

      _uuid ->
        attrs
    end
  end

  @spec normalize_app_uuid(String.t() | nil) :: String.t() | nil
  defp normalize_app_uuid(uuid) do
    uuid = uuid |> to_string() |> String.trim()

    if uuid == "" do
      nil
    else
      String.downcase(uuid)
    end
  end

  @spec inside_hidden_directory?(String.t()) :: boolean()
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
