defmodule Ide.Mcp.Handlers.Compiler do
  @moduledoc false

  alias Ide.Compiler
  alias Ide.Compiler.Diagnostics
  alias Ide.Compiler.Cache, as: CompileCache
  alias Ide.Compiler.ManifestCache
  alias Ide.Mcp.Audit
  alias Ide.Mcp.CheckCache
  alias Ide.Mcp.ToolSupport
  alias Ide.Mcp.ToolTypes
  alias Ide.Debugger
  alias Ide.Projects
  alias Ide.AppStore.Publisher, as: AppStorePublisher
  alias Ide.PublishManifest
  alias Ide.PublishReadiness
  alias Ide.PebbleToolchain
  alias Ide.Screenshots
  alias IdeWeb.WorkspaceLive.PublishFlow

  @type maybe_since :: DateTime.t() | nil

  defp mcp_tools_config, do: Application.get_env(:ide, Ide.Mcp.Tools, [])

  def call("compiler.check", %{"slug" => slug}) do
    compiler = compiler_module()

    with {:ok, project} <- ToolSupport.fetch_project(slug),
         session_key = Projects.scope_key(project),
         {:ok, result} <-
           compiler.check(session_key, workspace_root: Projects.project_workspace_path(project)) do
      diagnostics = Diagnostics.normalize_list(result.diagnostics || [])
      counts = Diagnostics.summary(diagnostics)
      :ok = CheckCache.put(session_key, result)

      {:ok, compiler_check_payload(slug, result, diagnostics, counts)}
    else
      {:error, reason} -> {:error, "check failed: #{inspect(reason)}"}
    end
  end

  def call("compiler.check_source_root", %{
         "slug" => slug,
         "source_root" => source_root
       }) do
    compiler = compiler_module()

    with {:ok, project} <- ToolSupport.fetch_project(slug) do
      if source_root in project.source_roots do
        with {:ok, result} <-
               compiler.check_source_root(Projects.compiler_cache_key(project, source_root),
                 workspace_root: Projects.project_workspace_path(project),
                 source_root: source_root
               ) do
          diagnostics = Diagnostics.normalize_list(result.diagnostics || [])
          counts = Diagnostics.summary(diagnostics)

          {:ok, compiler_check_source_root_payload(slug, source_root, result, diagnostics, counts)}
        else
          {:error, reason} -> {:error, "check source root failed: #{inspect(reason)}"}
        end
      else
        {:error, "check source root failed: :invalid_source_root"}
      end
    else
      {:error, reason} -> {:error, "check source root failed: #{inspect(reason)}"}
    end
  end
  def call("compiler.compile", %{"slug" => slug}) do
    compiler = compiler_module()

    with {:ok, project} <- ToolSupport.fetch_project(slug),
         session_key = Projects.scope_key(project),
         {:ok, result} <-
           compiler.compile(session_key, workspace_root: Projects.project_workspace_path(project)),
         :ok <- ingest_compile_result(slug, project, result) do
      diagnostics = Diagnostics.normalize_list(result.diagnostics || [])
      counts = Diagnostics.summary(diagnostics)

      {:ok, compiler_compile_payload(slug, result, diagnostics, counts)}
    else
      {:error, reason} -> {:error, "compile failed: #{inspect(reason)}"}
    end
  end

  def call("compiler.manifest", %{"slug" => slug, "strict" => strict}) do
    strict? = strict == true
    compiler = compiler_module()

    with {:ok, project} <- ToolSupport.fetch_project(slug),
         session_key = Projects.scope_key(project),
         {:ok, result} <-
           compiler.manifest(session_key,
             workspace_root: Projects.project_workspace_path(project),
             strict: strict?
           ) do
      diagnostics = Diagnostics.normalize_list(result.diagnostics || [])
      counts = Diagnostics.summary(diagnostics)

      {:ok, compiler_manifest_payload(slug, result, diagnostics, counts)}
    else
      {:error, reason} -> {:error, "manifest failed: #{inspect(reason)}"}
    end
  end

  def call("compiler.manifest", %{"slug" => slug}) do
    call("compiler.manifest", %{"slug" => slug, "strict" => false})
  end

  def call("publish.prepare", %{"slug" => slug}) do
    with {:ok, project} <- ToolSupport.fetch_project(slug),
         {:ok, package} <- package_for_publish(project),
         {:ok, context} <- publish_context(project, package),
         {:ok, manifest} <-
           PublishManifest.export(slug,
             artifact_path: package.artifact_path,
             screenshot_groups: context.screenshot_groups,
             required_targets: context.required_targets,
             readiness: context.readiness
           ),
         {:ok, release_notes} <-
           PublishManifest.export_release_notes(slug, context.validation.release_notes_md) do
      {:ok,
       publish_prepare_payload(slug, %{
         status: context.validation.status,
         artifact_path: package.artifact_path,
         app_root: package.app_root,
         required_targets: context.required_targets,
         readiness: context.readiness,
         checks: context.validation.checks,
         manifest_path: manifest.path,
         release_notes_path: release_notes.path,
         release_notes_md: context.validation.release_notes_md,
         build_result: package.build_result
       })}
    else
      {:error, reason} -> {:error, "publish prepare failed: #{inspect(reason)}"}
    end
  end

  def call("publish.validate", %{"slug" => slug} = args) do
    with {:ok, project} <- ToolSupport.fetch_project(slug),
         {:ok, package} <- resolve_publish_validation_package(project, args),
         {:ok, context} <- publish_context(project, package) do
      {:ok,
       publish_validate_payload(slug, %{
         status: context.validation.status,
         artifact_path: package.artifact_path,
         app_root: package.app_root,
         required_targets: context.required_targets,
         readiness: context.readiness,
         checks: context.validation.checks,
         release_notes_md: context.validation.release_notes_md,
         build_result: Map.get(package, :build_result)
       })}
    else
      {:error, reason} -> {:error, "publish validate failed: #{inspect(reason)}"}
    end
  end

  def call("publish.submit", %{"slug" => slug} = args) do
    with {:ok, project} <- ToolSupport.fetch_project(slug),
         {:ok, package} <- resolve_publish_submit_package(project, args),
         {:ok, context} <- publish_context(project, package),
         :ok <- ensure_publish_ready(context.validation),
         release_notes <- publish_submit_release_notes(args),
         {:ok, screenshot_paths} <-
           PublishFlow.stage_publish_screenshots(package.app_root, context.screenshot_groups),
         {:ok, result} <-
           app_store_publisher_module().publish(project,
             app_root: package.app_root,
             artifact_path: package.artifact_path,
             release_notes: release_notes,
             version: Map.get(args, "version") || publish_version(project),
             description: Map.get(args, "description") || publish_description(project),
             screenshots: screenshot_paths,
             is_published: Map.get(args, "is_published", true) == true,
             all_platforms: Map.get(args, "all_platforms", false) == true,
             gif_all_platforms: Map.get(args, "gif_all_platforms", false) == true,
             firebase_id_token: Map.get(args, "firebase_id_token"),
             store_icons:
               Ide.StoreAssets.publish_icon_paths(Projects.project_workspace_path(project))
           ) do
      {:ok,
       publish_submit_payload(slug, %{
         status: result.status,
         command: result.command,
         exit_code: result.exit_code,
         cwd: result.cwd,
         output: result.output,
         artifact_path: package.artifact_path,
         app_root: package.app_root,
         readiness: context.readiness,
         checks: context.validation.checks
       })}
    else
      {:error, reason} -> {:error, "publish submit failed: #{inspect(reason)}"}
    end
  end

  def call("compiler.compile_cached", %{"slug" => slug}) do
    case CompileCache.latest(ToolSupport.project_session_key(slug)) do
      {:ok, entry} ->
        {:ok, compiler_cached_payload(slug, entry, include_revision: true)}

      {:error, :not_found} ->
        {:error, "no cached compile result for #{slug}"}
    end
  end

  def call("compiler.compile_recent", args) do
    limit =
      args
      |> Map.get("limit", 20)
      |> ToolSupport.parse_limit()

    with {:ok, since} <- ToolSupport.parse_since(Map.get(args, "since")) do
      slug = Map.get(args, "slug")
      entries = CompileCache.recent(limit, ToolSupport.project_session_key(slug)) |> ToolSupport.filter_since(since)
      {:ok, compiler_recent_payload(entries, limit, slug, since)}
    end
  end

  def call("compiler.manifest_cached", %{"slug" => slug}) do
    case ManifestCache.latest(ToolSupport.project_session_key(slug)) do
      {:ok, entry} ->
        {:ok, compiler_cached_payload(slug, entry, include_revision: true)}

      {:error, :not_found} ->
        {:error, "no cached manifest result for #{slug}"}
    end
  end

  def call("compiler.manifest_recent", args) do
    limit =
      args
      |> Map.get("limit", 20)
      |> ToolSupport.parse_limit()

    with {:ok, since} <- ToolSupport.parse_since(Map.get(args, "since")) do
      slug = Map.get(args, "slug")
      entries = ManifestCache.recent(limit, ToolSupport.project_session_key(slug)) |> ToolSupport.filter_since(since)
      {:ok, compiler_recent_payload(entries, limit, slug, since)}
    end
  end

  def call("compiler.check_cached", %{"slug" => slug}) do
    case CheckCache.latest(ToolSupport.project_session_key(slug)) do
      {:ok, entry} ->
        {:ok, compiler_cached_payload(slug, entry)}

      {:error, :not_found} ->
        {:error, "no cached check result for #{slug}"}
    end
  end

  def call("compiler.check_recent", args) do
    limit =
      args
      |> Map.get("limit", 20)
      |> ToolSupport.parse_limit()

    with {:ok, since} <- ToolSupport.parse_since(Map.get(args, "since")) do
      slug = Map.get(args, "slug")
      entries = CheckCache.recent(limit, ToolSupport.project_session_key(slug)) |> ToolSupport.filter_since(since)
      {:ok, compiler_recent_payload(entries, limit, slug, since)}
    end
  end

  def call("audit.recent", args) do
    limit =
      args
      |> Map.get("limit", 20)
      |> ToolSupport.parse_limit()

    with {:ok, since} <- ToolSupport.parse_since(Map.get(args, "since")) do
      entries = Audit.recent(limit) |> ToolSupport.filter_since(since)
      {:ok, audit_recent_payload(entries, limit, since)}
    end
  end
  defp compiler_recent_payload(entries, limit, slug, since) do
    %{
      entries: entries,
      limit: limit,
      slug: slug,
      since: ToolSupport.format_since(since)
    }
  end

  @spec audit_recent_payload([map()], pos_integer(), DateTime.t() | nil) ::
          ToolTypes.audit_recent_result()
  defp audit_recent_payload(entries, limit, since) do
    %{entries: entries, limit: limit, since: ToolSupport.format_since(since)}
  end

  @spec compiler_check_payload(String.t(), Ide.Compiler.check_result(), [map()], map()) ::
          ToolTypes.compiler_check_result()
  defp compiler_check_payload(slug, result, diagnostics, counts) do
    %{
      slug: slug,
      status: result.status,
      checked_path: result.checked_path,
      diagnostics: diagnostics,
      error_count: counts.error_count,
      warning_count: counts.warning_count,
      output: result.output
    }
  end

  @spec compiler_check_source_root_payload(
          String.t(),
          String.t(),
          Ide.Compiler.check_result(),
          [map()],
          map()
        ) :: ToolTypes.compiler_check_result()
  defp compiler_check_source_root_payload(slug, source_root, result, diagnostics, counts) do
    %{
      slug: slug,
      source_root: source_root,
      status: result.status,
      checked_path: result.checked_path,
      diagnostics: diagnostics,
      error_count: counts.error_count,
      warning_count: counts.warning_count,
      output: result.output
    }
  end

  @spec compiler_compile_payload(
          String.t(),
          Ide.Compiler.compile_result(),
          [map()],
          map()
        ) :: ToolTypes.compiler_compile_result()
  defp compiler_compile_payload(slug, result, diagnostics, counts) do
    %{
      slug: slug,
      status: result.status,
      compiled_path: result.compiled_path,
      revision: result.revision,
      cached: result.cached?,
      diagnostics: diagnostics,
      error_count: counts.error_count,
      warning_count: counts.warning_count,
      output: result.output
    }
  end

  @spec normalize_compiler_status(String.t() | atom()) :: :ok | :error
  defp normalize_compiler_status(status) when status in [:ok, :error], do: status
  defp normalize_compiler_status("ok"), do: :ok
  defp normalize_compiler_status(_), do: :error

  @spec compiler_manifest_payload(String.t(), map(), [map()], map()) ::
          ToolTypes.compiler_manifest_result()
  defp compiler_manifest_payload(slug, result, diagnostics, counts) when is_map(result) do
    %{
      slug: slug,
      status: normalize_compiler_status(Map.get(result, :status)),
      manifest_path: Map.get(result, :manifest_path, ""),
      revision: Map.get(result, :revision, ""),
      cached: Map.get(result, :cached?) == true or Map.get(result, :cached) == true,
      strict: Map.get(result, :strict?) == true or Map.get(result, :strict) == true,
      manifest: Map.get(result, :manifest),
      diagnostics: diagnostics,
      error_count: counts.error_count,
      warning_count: counts.warning_count,
      output: Map.get(result, :output, "")
    }
  end

  defp compiler_cached_payload(slug, entry, opts \\ []) when is_map(entry) do
    base = %{
      slug: slug,
      cached: true,
      at: Map.fetch!(entry, :at),
      result: Map.fetch!(entry, :result)
    }

    if Keyword.get(opts, :include_revision, false) do
      Map.put(base, :revision, Map.fetch!(entry, :revision))
    else
      base
    end
  end

  @spec publish_prepare_payload(String.t(), map()) :: ToolTypes.publish_prepare_result()
  defp publish_prepare_payload(slug, fields) when is_map(fields) do
    %{slug: slug, status: Map.fetch!(fields, :status)}
    |> Map.merge(Map.drop(fields, [:status]))
  end

  @spec publish_submit_payload(String.t(), map()) :: ToolTypes.publish_submit_result()
  defp publish_submit_payload(slug, fields) when is_map(fields) do
    %{slug: slug, status: Map.fetch!(fields, :status)}
    |> Map.merge(Map.drop(fields, [:status]))
  end

  @spec publish_validate_payload(String.t(), map()) :: ToolTypes.publish_validate_result()
  defp publish_validate_payload(slug, fields) when is_map(fields) do
    %{slug: slug, status: Map.fetch!(fields, :status)}
    |> Map.merge(Map.drop(fields, [:status]))
  end

  @spec ingest_compile_result(String.t(), map(), map()) :: :ok
  defp ingest_compile_result(slug, project, result)
       when is_binary(slug) and is_map(result) do
    attrs =
      result
      |> Map.put_new(:source_root, compile_result_source_root(project, result))

    {:ok, _state} = Debugger.ingest_elmc_compile(Projects.scope_key(project), attrs)
    :ok
  end

  defp ingest_compile_result(_slug, _project, _result), do: :ok

  @spec compile_result_source_root(map(), map()) :: String.t()
  defp compile_result_source_root(project, result) when is_map(result) do
    workspace = Projects.project_workspace_path(project)
    compiled_path = Map.get(result, :compiled_path) || Map.get(result, "compiled_path")

    with path when is_binary(path) <- compiled_path,
         relative when relative != path <- Path.relative_to(path, workspace),
         [source_root | _] <- Path.split(relative) do
      if source_root in project.source_roots do
        source_root
      else
        List.first(project.source_roots) || "watch"
      end
    else
      _ -> List.first(project.source_roots) || "watch"
    end
  end

  defp package_for_publish(project) do
    toolchain = pebble_toolchain_module()

    toolchain.package(project.slug,
      workspace_root: Projects.project_workspace_path(project),
      target_type: project.target_type,
      project_name: project.name,
      target_platforms: ToolSupport.publish_target_platforms(project),
      version: publish_version(project),
      description: publish_description(project),
      capabilities: publish_capabilities(project)
    )
  end

  defp resolve_publish_validation_package(project, args) do
    if is_map(args) and Map.get(args, "package") == false do
      {:ok,
       %{
         status: :unknown,
         artifact_path: Map.get(args, "artifact_path"),
         app_root: Map.get(args, "app_root"),
         build_result: nil
       }}
    else
      package_for_publish(project)
    end
  end

  defp resolve_publish_submit_package(_project, %{"app_root" => app_root} = args)
       when is_binary(app_root) and app_root != "" do
    {:ok,
     %{
       status: :unknown,
       artifact_path: Map.get(args, "artifact_path"),
       app_root: app_root,
       build_result: nil
     }}
  end

  defp resolve_publish_submit_package(project, _args), do: package_for_publish(project)

  defp publish_context(project, package) do
    screenshots = screenshots_module()
    required_targets = ToolSupport.publish_target_platforms(project)

    with {:ok, shots} <- screenshots.list(project.slug, []),
         readiness <- publish_readiness(shots, required_targets),
         screenshot_groups <- group_publish_screenshots(shots),
         {:ok, validation} <-
           PublishReadiness.validate(
             artifact_path: package.artifact_path,
             required_targets: required_targets,
             readiness: readiness,
             app_root: package.app_root,
             project_slug: project.slug
           ) do
      {:ok,
       %{
         required_targets: required_targets,
         readiness: readiness,
         screenshot_groups: screenshot_groups,
         validation: validation
       }}
    end
  end

  defp publish_readiness(shots, targets) do
    counts =
      shots
      |> Enum.group_by(& &1.emulator_target)
      |> Map.new(fn {target, values} -> {target, length(values)} end)

    Enum.map(targets, fn target ->
      count = Map.get(counts, target, 0)
      %{target: target, count: count, status: if(count > 0, do: :ok, else: :missing)}
    end)
  end

  defp group_publish_screenshots(shots) do
    shots
    |> Enum.group_by(& &1.emulator_target)
    |> Enum.sort_by(fn {target, _shots} -> target end)
  end

  defp ensure_publish_ready(%{status: :ok}), do: :ok
  defp ensure_publish_ready(validation), do: {:error, {:publish_not_ready, validation.checks}}

  defp publish_capabilities(project) do
    defaults = Map.get(project, :release_defaults) || %{}

    defaults
    |> Map.get("capabilities", [])
    |> List.wrap()
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp publish_version(project) do
    project
    |> publish_defaults()
    |> Map.get("version_label", "")
    |> to_string()
    |> String.trim()
  end

  defp publish_description(project) do
    project
    |> publish_defaults()
    |> Map.get("description", "")
    |> to_string()
    |> String.trim()
  end

  defp publish_submit_release_notes(args) when is_map(args) do
    case Map.get(args, "release_notes") do
      notes when is_binary(notes) -> String.trim(notes)
      _ -> ""
    end
  end

  defp publish_defaults(project), do: Map.get(project, :release_defaults) || %{}


  defp pebble_toolchain_module do
    mcp_tools_config()
    |> Keyword.get(:pebble_toolchain_module, PebbleToolchain)
  end

  defp screenshots_module do
    mcp_tools_config()
    |> Keyword.get(:screenshots_module, Screenshots)
  end

  defp app_store_publisher_module do
    mcp_tools_config()
    |> Keyword.get(:app_store_publisher_module, AppStorePublisher)
  end

  defp compiler_module do
    mcp_tools_config()
    |> Keyword.get(:compiler_module, Compiler)
  end
end
