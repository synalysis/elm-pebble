defmodule Ide.Mcp.Handlers.Traces do
  @moduledoc false

  alias Ide.Compiler.Cache, as: CompileCache
  alias Ide.Compiler.ManifestCache
  alias Ide.Mcp.Audit
  alias Ide.Mcp.CheckCache
  alias Ide.Mcp.ToolSupport
  alias Ide.Mcp.ToolTypes
  alias Ide.Mcp.WireTypes
  alias Ide.Projects
  alias Ide.Screenshots

  @type maybe_since :: DateTime.t() | nil
  @type maybe_slug :: String.t() | nil
  @type maybe_trace_id :: String.t() | nil

  defp mcp_tools_config, do: Application.get_env(:ide, Ide.Mcp.Tools, [])

  def call("traces.bundle", args) do
    with {:ok, bundle} <- build_trace_bundle(args) do
      {:ok, bundle}
    end
  end

  def call("traces.summary", args) do
    with {:ok, bundle} <- build_trace_bundle(args) do
      checks = bundle.compiler_context.recent.checks
      compiles = bundle.compiler_context.recent.compiles
      manifests = bundle.compiler_context.recent.manifests
      actions = bundle.audit_entries

      {:ok, traces_summary_payload(bundle, actions, checks, compiles, manifests)}
    end
  end

  def call("traces.export", args), do: export_trace(args)

  def call("traces.exports_list", args) do
    limit =
      args
      |> Map.get("limit", 50)
      |> ToolSupport.parse_limit()

    with {:ok, files} <- read_trace_export_files() do
      entries =
        files
        |> Enum.take(limit)
        |> Enum.map(&trace_export_file_entry/1)

      {:ok, traces_exports_list_payload(entries, limit, length(files))}
    else
      {:error, reason} -> {:error, "trace exports list failed: #{inspect(reason)}"}
    end
  end

  def call("traces.policy", _args) do
    {:ok, traces_policy_payload()}
  end

  def call("traces.policy_validate", _args) do
    effective = trace_policy_effective_settings()

    {:ok, traces_policy_validate_payload(effective)}
  end

  def call("traces.export_write", args) do
    with {:ok, export} <- export_trace(args),
         :ok <- File.mkdir_p(trace_export_dir()),
         file_name <- trace_export_filename(export),
         absolute_path <- Path.join(trace_export_dir(), file_name),
         :ok <- File.write(absolute_path, export.export_json),
         {:ok, stat} <- File.stat(absolute_path) do
      {:ok, traces_export_write_payload(export, stat.size, absolute_path, file_name)}
    else
      {:error, reason} -> {:error, "trace export write failed: #{inspect(reason)}"}
    end
  end

  def call("traces.exports_prune", args) do
    keep_latest =
      args
      |> Map.get("keep_latest", default_keep_latest())
      |> parse_prune_keep_latest()

    with {:ok, files} <- read_trace_export_files() do
      to_delete = Enum.drop(files, keep_latest)

      deleted =
        Enum.reduce(to_delete, [], fn file, acc ->
          case File.rm(file.path) do
            :ok -> [file.file_name | acc]
            {:error, _} -> acc
          end
        end)
        |> Enum.reverse()

      {:ok,
       traces_exports_prune_payload(keep_latest, deleted, max(length(files) - length(deleted), 0))}
    else
      {:error, reason} -> {:error, "trace exports prune failed: #{inspect(reason)}"}
    end
  end

  def call("traces.maintenance", args) do
    warn_count =
      ToolSupport.parse_positive_integer(Map.get(args, "warn_count"), default_warn_count())

    warn_bytes =
      ToolSupport.parse_positive_integer(Map.get(args, "warn_bytes"), default_warn_bytes())

    target_keep_latest =
      parse_prune_keep_latest(Map.get(args, "target_keep_latest", default_target_keep_latest()))

    apply? = Map.get(args, "apply") == true

    policy = %{
      warn_count: warn_count,
      warn_bytes: warn_bytes,
      keep_latest: default_keep_latest(),
      target_keep_latest: target_keep_latest
    }

    policy_validation = policy_validation_payload(policy)

    with {:ok, before} <- trace_health_payload(warn_count, warn_bytes) do
      should_prune? = before.status == "warn"
      pruned = apply? and should_prune?

      prune_result =
        if pruned do
          case call("traces.exports_prune", %{"keep_latest" => target_keep_latest}) do
            {:ok, result} -> {:ok, result}
            {:error, reason} -> {:error, reason}
          end
        else
          {:ok, traces_maintenance_prune_skipped_payload(before.trace_exports.total_count)}
        end

      with {:ok, prune_payload} <- prune_result,
           {:ok, health_after} <- trace_health_payload(warn_count, warn_bytes) do
        {:ok,
         traces_maintenance_payload(
           apply?,
           pruned,
           policy_validation,
           before,
           health_after,
           warn_count,
           warn_bytes,
           target_keep_latest,
           prune_payload
         )}
      else
        {:error, reason} -> {:error, "trace maintenance failed: #{inspect(reason)}"}
      end
    else
      {:error, reason} -> {:error, "trace maintenance failed: #{inspect(reason)}"}
    end
  end

  def call("sessions.recent_activity", args) do
    limit =
      args
      |> Map.get("limit", 20)
      |> ToolSupport.parse_limit()

    with {:ok, since} <- ToolSupport.parse_since(Map.get(args, "since")) do
      requested_slug = Map.get(args, "slug")

      projects =
        Projects.list_projects()
        |> maybe_filter_projects(requested_slug)
        |> Enum.map(fn project ->
          checks =
            CheckCache.recent(limit, ToolSupport.project_session_key(project))
            |> ToolSupport.filter_since(since)

          latest_check =
            case CheckCache.latest(ToolSupport.project_session_key(project)) do
              {:ok, entry} -> if ToolSupport.keep_since?(entry, since), do: entry, else: nil
              {:error, :not_found} -> nil
            end

          latest_compile =
            case CompileCache.latest(ToolSupport.project_session_key(project)) do
              {:ok, entry} -> if ToolSupport.keep_since?(entry, since), do: entry, else: nil
              {:error, :not_found} -> nil
            end

          latest_manifest =
            case ManifestCache.latest(ToolSupport.project_session_key(project)) do
              {:ok, entry} -> if ToolSupport.keep_since?(entry, since), do: entry, else: nil
              {:error, :not_found} -> nil
            end

          latest_manifest_strict =
            case latest_manifest do
              %{result: result} when is_map(result) -> result[:strict?]
              _ -> nil
            end

          %{
            slug: project.slug,
            name: project.name,
            target_type: project.target_type,
            active: project.active,
            screenshot_count: screenshot_count(project),
            latest_check: latest_check,
            latest_compile: latest_compile,
            latest_manifest: latest_manifest,
            latest_manifest_strict: latest_manifest_strict,
            recent_checks: checks,
            recent_compiles:
              CompileCache.recent(limit, ToolSupport.project_session_key(project))
              |> ToolSupport.filter_since(since),
            recent_manifests:
              ManifestCache.recent(limit, ToolSupport.project_session_key(project))
              |> ToolSupport.filter_since(since),
            recent_actions: recent_project_actions(project.slug, limit, since)
          }
        end)

      {:ok, sessions_recent_activity_payload(projects, limit, requested_slug, since)}
    end
  end

  def call("sessions.summary", args) do
    with {:ok, since} <- ToolSupport.parse_since(Map.get(args, "since")) do
      requested_slug = Map.get(args, "slug")

      summaries =
        Projects.list_projects()
        |> maybe_filter_projects(requested_slug)
        |> Enum.map(&session_project_summary(&1, since))

      {:ok, sessions_summary_payload(summaries, requested_slug, since)}
    end
  end

  def call("sessions.trace_health", args) do
    warn_count =
      ToolSupport.parse_positive_integer(Map.get(args, "warn_count"), default_warn_count())

    warn_bytes =
      ToolSupport.parse_positive_integer(Map.get(args, "warn_bytes"), default_warn_bytes())

    policy = %{
      warn_count: warn_count,
      warn_bytes: warn_bytes,
      keep_latest: default_keep_latest(),
      target_keep_latest: default_target_keep_latest()
    }

    policy_validation = policy_validation_payload(policy)

    with {:ok, health} <- trace_health_payload(warn_count, warn_bytes) do
      {:ok, sessions_trace_health_payload(health, policy_validation)}
    else
      {:error, reason} -> {:error, "trace health failed: #{inspect(reason)}"}
    end
  end

  defp export_trace(args) do
    with {:ok, bundle} <- build_trace_bundle(args) do
      payload = %{export_version: 1, trace_bundle: bundle}
      export_json = encode_canonical_json(payload)

      export_sha256 =
        :crypto.hash(:sha256, export_json)
        |> Base.encode16(case: :lower)

      {:ok, traces_export_payload(bundle, export_json, export_sha256)}
    end
  end

  @spec session_project_summary(Ide.Projects.Project.t(), DateTime.t() | nil) ::
          ToolTypes.sessions_summary_entry()
  defp session_project_summary(%Ide.Projects.Project{} = project, since) do
    recent_checks =
      CheckCache.recent(50, ToolSupport.project_session_key(project))
      |> ToolSupport.filter_since(since)

    recent_actions = recent_project_actions(project.slug, 100, since)

    %{
      slug: project.slug,
      active: project.active,
      target_type: project.target_type,
      latest_check_status:
        ToolSupport.cache_latest_result_field(
          CheckCache,
          ToolSupport.project_session_key(project),
          since,
          :status
        ),
      latest_compile_status:
        ToolSupport.cache_latest_result_field(
          CompileCache,
          ToolSupport.project_session_key(project),
          since,
          :status
        ),
      latest_manifest_status:
        ToolSupport.cache_latest_result_field(
          ManifestCache,
          ToolSupport.project_session_key(project),
          since,
          :status
        ),
      latest_manifest_strict:
        ToolSupport.cache_latest_result_field(
          ManifestCache,
          ToolSupport.project_session_key(project),
          since,
          :strict?
        ),
      checks_count: length(recent_checks),
      compiles_count:
        length(
          CompileCache.recent(50, ToolSupport.project_session_key(project))
          |> ToolSupport.filter_since(since)
        ),
      manifests_count:
        length(
          ManifestCache.recent(50, ToolSupport.project_session_key(project))
          |> ToolSupport.filter_since(since)
        ),
      actions_count: length(recent_actions),
      screenshots_count: screenshot_count(project)
    }
  end

  defp sessions_recent_activity_payload(projects, limit, slug, since) do
    %{projects: projects, limit: limit, slug: slug, since: ToolSupport.format_since(since)}
  end

  @spec sessions_summary_payload(
          [ToolTypes.sessions_summary_entry()],
          String.t() | nil,
          DateTime.t() | nil
        ) :: ToolTypes.sessions_summary_result()
  defp sessions_summary_payload(summaries, slug, since) do
    %{projects: summaries, slug: slug, since: ToolSupport.format_since(since)}
  end

  @spec sessions_trace_health_payload(
          ToolTypes.trace_health_status_result(),
          ToolTypes.policy_validation_result()
        ) ::
          ToolTypes.sessions_trace_health_result()
  defp sessions_trace_health_payload(health, policy_validation)
       when is_map(health) and is_map(policy_validation) do
    Map.put(health, :policy_validation, policy_validation)
  end

  @spec trace_export_file_entry(ToolTypes.trace_export_file_internal()) ::
          ToolTypes.trace_export_file_entry()
  defp trace_export_file_entry(file) when is_map(file) do
    %{
      file_name: Map.fetch!(file, :file_name),
      path: Map.fetch!(file, :path),
      bytes: Map.fetch!(file, :bytes),
      modified_at: Map.get(file, :modified_at)
    }
  end

  @spec trace_policy_effective_settings() :: ToolTypes.traces_policy_effective_settings()
  defp trace_policy_effective_settings do
    %{
      warn_count: default_warn_count(),
      warn_bytes: default_warn_bytes(),
      keep_latest: default_keep_latest(),
      target_keep_latest: default_target_keep_latest()
    }
  end

  @spec trace_policy_settings_map(keyword()) :: ToolTypes.traces_policy_configured_settings()
  defp trace_policy_settings_map(policy) when is_list(policy) do
    %{
      warn_count: Keyword.get(policy, :warn_count),
      warn_bytes: Keyword.get(policy, :warn_bytes),
      keep_latest: Keyword.get(policy, :keep_latest),
      target_keep_latest: Keyword.get(policy, :target_keep_latest)
    }
  end

  @spec traces_export_payload(ToolTypes.trace_bundle(), String.t(), String.t()) ::
          ToolTypes.traces_export_result()
  defp traces_export_payload(bundle, export_json, export_sha256)
       when is_map(bundle) and is_binary(export_json) and is_binary(export_sha256) do
    %{
      trace_id: Map.get(bundle, :trace_id),
      slug: Map.get(bundle, :slug),
      since: Map.get(bundle, :since),
      limit: Map.get(bundle, :limit),
      export_sha256: export_sha256,
      export_json: export_json
    }
  end

  @spec traces_export_write_payload(map(), non_neg_integer(), String.t(), String.t()) ::
          ToolTypes.traces_export_write_result()
  defp traces_export_write_payload(export, bytes, path, file_name)
       when is_map(export) and is_integer(bytes) and is_binary(path) and is_binary(file_name) do
    %{
      trace_id: Map.get(export, :trace_id),
      slug: Map.get(export, :slug),
      export_sha256: Map.fetch!(export, :export_sha256),
      bytes: bytes,
      path: path,
      file_name: file_name
    }
  end

  @spec traces_exports_list_payload(
          [ToolTypes.trace_export_file_entry()],
          pos_integer(),
          non_neg_integer()
        ) ::
          ToolTypes.traces_exports_list_result()
  defp traces_exports_list_payload(entries, limit, total_available) do
    %{entries: entries, limit: limit, total_available: total_available}
  end

  @spec traces_exports_prune_payload(pos_integer(), [String.t()], non_neg_integer()) ::
          ToolTypes.traces_exports_prune_result()
  defp traces_exports_prune_payload(keep_latest, deleted_files, remaining_count)
       when is_integer(keep_latest) and is_list(deleted_files) and is_integer(remaining_count) do
    %{
      keep_latest: keep_latest,
      deleted_count: length(deleted_files),
      deleted_files: deleted_files,
      remaining_count: remaining_count
    }
  end

  @spec traces_maintenance_payload(
          boolean(),
          boolean(),
          ToolTypes.policy_validation_result(),
          ToolTypes.trace_health_status_result(),
          ToolTypes.trace_health_status_result(),
          pos_integer(),
          pos_integer(),
          pos_integer(),
          ToolTypes.traces_exports_prune_result() | ToolTypes.traces_maintenance_prune_skipped()
        ) :: ToolTypes.traces_maintenance_result()
  defp traces_maintenance_payload(
         apply?,
         pruned,
         policy_validation,
         health_before,
         health_after,
         warn_count,
         warn_bytes,
         target_keep_latest,
         prune_payload
       )
       when is_boolean(apply?) and is_boolean(pruned) and is_map(policy_validation) and
              is_map(health_before) and is_map(health_after) and is_map(prune_payload) do
    %{
      mode: if(apply?, do: "apply", else: "dry_run"),
      status: if(pruned, do: "pruned", else: "no_change"),
      policy_validation: policy_validation,
      health_before: health_before,
      health_after: health_after,
      thresholds: %{warn_count: warn_count, warn_bytes: warn_bytes},
      target_keep_latest: target_keep_latest,
      prune: prune_payload
    }
  end

  @spec traces_maintenance_prune_skipped_payload(non_neg_integer()) ::
          ToolTypes.traces_maintenance_prune_skipped()
  defp traces_maintenance_prune_skipped_payload(remaining_count)
       when is_integer(remaining_count) do
    %{deleted_count: 0, deleted_files: [], remaining_count: remaining_count}
  end

  @spec traces_policy_payload() :: ToolTypes.traces_policy_result()
  defp traces_policy_payload do
    configured = trace_policy()

    %{
      configured: trace_policy_settings_map(configured),
      effective: trace_policy_effective_settings()
    }
  end

  @spec traces_policy_validate_payload(ToolTypes.traces_policy_effective_settings()) ::
          ToolTypes.traces_policy_validate_result()
  defp traces_policy_validate_payload(effective) when is_map(effective) do
    validation = policy_validation_payload(effective)

    %{status: validation.status, policy: effective, findings: validation.findings}
  end

  @spec traces_summary_payload(map(), [map()], [map()], [map()], [map()]) ::
          ToolTypes.traces_summary_result()
  defp traces_summary_payload(bundle, actions, checks, compiles, manifests) when is_map(bundle) do
    %{
      trace_id: Map.get(bundle, :trace_id),
      slug: Map.get(bundle, :slug),
      since: Map.get(bundle, :since),
      window: %{
        limit: Map.get(bundle, :limit),
        audit_entries: length(actions),
        checks: length(checks),
        compiles: length(compiles),
        manifests: length(manifests)
      },
      latest_status: %{
        check: status_of_entry(get_in(bundle, [:compiler_context, :latest, :check])),
        compile: status_of_entry(get_in(bundle, [:compiler_context, :latest, :compile])),
        manifest: status_of_entry(get_in(bundle, [:compiler_context, :latest, :manifest])),
        manifest_strict: strict_of_entry(get_in(bundle, [:compiler_context, :latest, :manifest]))
      },
      actions: action_counts(actions)
    }
  end

  @spec build_trace_bundle(map()) ::
          {:ok, ToolTypes.trace_bundle()} | {:error, String.t()}
  defp build_trace_bundle(args) do
    limit =
      args
      |> Map.get("limit", 20)
      |> ToolSupport.parse_limit()

    with {:ok, since} <- ToolSupport.parse_since(Map.get(args, "since")),
         {:ok, trace_id} <- ToolSupport.parse_trace_id(Map.get(args, "trace_id")),
         {:ok, requested_slug} <- ToolSupport.parse_optional_slug(Map.get(args, "slug")) do
      audit_entries =
        Audit.recent(limit * 5)
        |> maybe_filter_trace_id(trace_id)
        |> maybe_filter_audit_slug(requested_slug)
        |> ToolSupport.filter_since(since)
        |> Enum.take(limit)

      slug = requested_slug || infer_slug_from_audit_entries(audit_entries)

      session_key = if is_binary(slug), do: ToolSupport.project_session_key(slug), else: nil

      check_entries = CheckCache.recent(limit, session_key) |> ToolSupport.filter_since(since)
      compile_entries = CompileCache.recent(limit, session_key) |> ToolSupport.filter_since(since)

      manifest_entries =
        ManifestCache.recent(limit, session_key) |> ToolSupport.filter_since(since)

      {:ok,
       %{
         trace_id: trace_id,
         slug: slug,
         limit: limit,
         since: ToolSupport.format_since(since),
         audit_entries: audit_entries,
         compiler_context: %{
           latest: %{
             check: latest_entry(CheckCache, session_key, since),
             compile: latest_entry(CompileCache, session_key, since),
             manifest: latest_entry(ManifestCache, session_key, since)
           },
           recent: %{
             checks: check_entries,
             compiles: compile_entries,
             manifests: manifest_entries
           }
         }
       }}
    end
  end

  defp maybe_filter_projects(projects, nil), do: projects
  defp maybe_filter_projects(projects, slug), do: Enum.filter(projects, &(&1.slug == slug))

  @spec recent_project_actions(String.t(), pos_integer(), maybe_since()) :: [map()]
  defp recent_project_actions(project_slug, limit, since) do
    Audit.recent(limit * 5)
    |> Enum.filter(fn entry ->
      args = Map.get(entry, "arguments", %{})
      Map.get(args, "slug") == project_slug
    end)
    |> ToolSupport.filter_since(since)
    |> Enum.take(limit)
  end

  defp screenshot_count(%Projects.Project{} = project) do
    case Screenshots.list(project, []) do
      {:ok, shots} -> length(shots)
      {:error, _reason} -> 0
    end
  end

  defp screenshot_count(project_slug) when is_binary(project_slug) do
    case Screenshots.list(project_slug, []) do
      {:ok, shots} -> length(shots)
      {:error, _reason} -> 0
    end
  end

  defp parse_prune_keep_latest(value) when is_integer(value), do: max(value, 0)

  defp parse_prune_keep_latest(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _} -> max(parsed, 0)
      _ -> default_keep_latest()
    end
  end

  defp parse_prune_keep_latest(_), do: default_keep_latest()
  @spec maybe_filter_trace_id([map()], maybe_trace_id()) :: [map()]
  defp maybe_filter_trace_id(entries, nil), do: entries

  defp maybe_filter_trace_id(entries, trace_id),
    do: Enum.filter(entries, &(&1["trace_id"] == trace_id))

  @spec maybe_filter_audit_slug([map()], maybe_slug()) :: [map()]
  defp maybe_filter_audit_slug(entries, nil), do: entries

  defp maybe_filter_audit_slug(entries, slug) do
    Enum.filter(entries, fn entry ->
      entry
      |> Map.get("arguments", %{})
      |> Map.get("slug") == slug
    end)
  end

  @spec infer_slug_from_audit_entries([map()]) :: maybe_slug()
  defp infer_slug_from_audit_entries(entries) do
    entries
    |> Enum.find_value(fn entry ->
      entry
      |> Map.get("arguments", %{})
      |> Map.get("slug")
    end)
  end

  @spec latest_entry(module(), maybe_slug(), maybe_since()) :: map() | nil
  defp latest_entry(_cache_module, nil, _since), do: nil

  defp latest_entry(cache_module, slug, since) do
    case cache_module.latest(slug) do
      {:ok, entry} -> if ToolSupport.keep_since?(entry, since), do: entry, else: nil
      {:error, :not_found} -> nil
    end
  end

  @spec status_of_entry(map() | nil) :: :ok | :error | String.t() | nil
  defp status_of_entry(nil), do: nil

  defp status_of_entry(entry) when is_map(entry) do
    entry
    |> Map.get(:result, %{})
    |> Map.get(:status)
  end

  @spec strict_of_entry(map() | nil) :: boolean() | nil
  defp strict_of_entry(nil), do: nil

  defp strict_of_entry(entry) when is_map(entry) do
    entry
    |> Map.get(:result, %{})
    |> Map.get(:strict?)
  end

  @spec action_counts([map()]) :: [map()]
  defp action_counts(entries) when is_list(entries) do
    entries
    |> Enum.group_by(&Map.get(&1, "action", "unknown"))
    |> Enum.map(fn {action, grouped} ->
      %{
        action: action,
        total: length(grouped),
        ok: Enum.count(grouped, &(Map.get(&1, "status") == "ok")),
        error: Enum.count(grouped, &(Map.get(&1, "status") == "error"))
      }
    end)
    |> Enum.sort_by(& &1.action)
  end

  @spec encode_canonical_json(WireTypes.json_value() | map()) :: String.t()
  defp encode_canonical_json(value) when is_map(value) do
    members =
      value
      |> Enum.map(fn {key, member} -> {to_string(key), member} end)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map_join(",", fn {key, member} ->
        Jason.encode!(key) <> ":" <> encode_canonical_json(member)
      end)

    "{" <> members <> "}"
  end

  defp encode_canonical_json(value) when is_list(value) do
    "[" <> Enum.map_join(value, ",", &encode_canonical_json/1) <> "]"
  end

  defp encode_canonical_json(value), do: Jason.encode!(value)

  defp trace_export_filename(export) do
    slug = sanitize_segment(export.slug || "all")
    trace = sanitize_segment(export.trace_id || "all")
    "trace-export-#{slug}-#{trace}-#{export.export_sha256}.json"
  end

  @spec sanitize_segment(String.t()) :: String.t()
  defp sanitize_segment(value) when is_binary(value) do
    value
    |> String.replace(~r/[^A-Za-z0-9._-]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "all"
      cleaned -> cleaned
    end
  end

  @spec trace_export_dir() :: String.t()
  defp trace_export_dir do
    Path.join(:code.priv_dir(:ide), "mcp/trace_exports")
  end

  @spec read_trace_export_files() ::
          {:ok, [ToolTypes.trace_export_file_internal()]}
          | {:error, ToolTypes.tool_persist_error()}
  defp read_trace_export_files do
    case File.ls(trace_export_dir()) do
      {:ok, names} ->
        entries =
          names
          |> Enum.filter(&String.ends_with?(&1, ".json"))
          |> Enum.map(fn file_name ->
            path = Path.join(trace_export_dir(), file_name)

            with {:ok, stat} <- File.stat(path),
                 {:ok, modified_at} <- NaiveDateTime.from_erl(stat.mtime) do
              %{
                file_name: file_name,
                path: path,
                bytes: stat.size,
                modified_at:
                  DateTime.from_naive!(modified_at, "Etc/UTC") |> DateTime.to_iso8601(),
                sort_key: stat.mtime
              }
            else
              _ -> nil
            end
          end)
          |> Enum.reject(&is_nil/1)
          |> Enum.sort_by(& &1.sort_key, :desc)

        {:ok, entries}

      {:error, :enoent} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec trace_health_payload(pos_integer(), pos_integer()) ::
          {:ok, ToolTypes.trace_health_status_result()} | {:error, ToolTypes.tool_persist_error()}
  defp trace_health_payload(warn_count, warn_bytes) do
    with {:ok, files} <- read_trace_export_files() do
      total_count = length(files)
      total_bytes = Enum.reduce(files, 0, fn file, acc -> file.bytes + acc end)
      newest = files |> List.first() |> then(&(&1 && &1.modified_at))
      oldest = files |> List.last() |> then(&(&1 && &1.modified_at))

      over_count = total_count > warn_count
      over_bytes = total_bytes > warn_bytes

      status =
        if over_count or over_bytes do
          "warn"
        else
          "ok"
        end

      recommendation =
        cond do
          over_count and over_bytes ->
            "Prune exports by count and size pressure."

          over_count ->
            "Prune exports to reduce file count."

          over_bytes ->
            "Prune exports to reduce disk usage."

          true ->
            "No cleanup needed."
        end

      suggested_keep_latest =
        cond do
          total_count <= warn_count -> total_count
          true -> warn_count
        end

      {:ok,
       %{
         status: status,
         recommendation: recommendation,
         trace_exports: %{
           total_count: total_count,
           total_bytes: total_bytes,
           newest_modified_at: newest,
           oldest_modified_at: oldest
         },
         thresholds: %{
           warn_count: warn_count,
           warn_bytes: warn_bytes
         },
         suggested_keep_latest: suggested_keep_latest
       }}
    end
  end

  @spec validate_trace_policy(map()) :: [map()]
  defp validate_trace_policy(policy) when is_map(policy) do
    []
    |> maybe_add_finding(
      policy.warn_count <= 0,
      "error",
      "warn_count_non_positive",
      "warn_count should be greater than zero."
    )
    |> maybe_add_finding(
      policy.warn_bytes <= 0,
      "error",
      "warn_bytes_non_positive",
      "warn_bytes should be greater than zero."
    )
    |> maybe_add_finding(
      policy.target_keep_latest > policy.keep_latest,
      "warning",
      "target_keep_exceeds_keep",
      "target_keep_latest is higher than keep_latest; prune target may be ineffective."
    )
    |> maybe_add_finding(
      policy.keep_latest > policy.warn_count,
      "warning",
      "keep_exceeds_warn_count",
      "keep_latest is higher than warn_count; maintenance may remain in warning state after prune."
    )
    |> maybe_add_finding(
      policy.warn_bytes < 1_048_576,
      "warning",
      "warn_bytes_low",
      "warn_bytes is below 1 MiB; this may cause noisy maintenance warnings."
    )
  end

  @spec findings_status([map()]) :: String.t()
  defp findings_status(findings) when is_list(findings) do
    cond do
      Enum.any?(findings, &(&1.severity == "error")) -> "error"
      findings != [] -> "warn"
      true -> "ok"
    end
  end

  @spec policy_validation_payload(map()) :: ToolTypes.policy_validation_result()
  defp policy_validation_payload(policy) when is_map(policy) do
    findings = validate_trace_policy(policy)
    %{status: findings_status(findings), findings: findings}
  end

  @spec maybe_add_finding([map()], boolean(), String.t(), String.t(), String.t()) :: [map()]
  defp maybe_add_finding(findings, condition, severity, code, message)
       when is_boolean(condition) do
    if condition do
      findings ++ [%{severity: severity, code: code, message: message}]
    else
      findings
    end
  end

  @spec default_warn_count() :: pos_integer()
  defp default_warn_count do
    trace_policy()
    |> Keyword.get(:warn_count, 200)
  end

  @spec default_warn_bytes() :: pos_integer()
  defp default_warn_bytes do
    trace_policy()
    |> Keyword.get(:warn_bytes, 50 * 1024 * 1024)
  end

  @spec default_keep_latest() :: non_neg_integer()
  defp default_keep_latest do
    trace_policy()
    |> Keyword.get(:keep_latest, 50)
  end

  @spec default_target_keep_latest() :: non_neg_integer()
  defp default_target_keep_latest do
    trace_policy()
    |> Keyword.get(:target_keep_latest, default_keep_latest())
  end

  @spec trace_policy() :: keyword()
  defp trace_policy do
    mcp_tools_config()
    |> Keyword.get(:trace_policy, [])
  end
end
