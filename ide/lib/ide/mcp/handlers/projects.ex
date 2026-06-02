defmodule Ide.Mcp.Handlers.Projects do
  @moduledoc false

  alias Ide.Debugger
  alias Ide.EmulatorSupport
  alias Ide.Mcp.ToolSupport
  alias Ide.Mcp.ToolTypes
  alias Ide.Mcp.WireTypes
  alias Ide.ProjectTemplates
  alias Ide.Projects
  alias Ide.Projects.BootstrapError

  def call("templates.list", _args) do
    {:ok, %{templates: ProjectTemplates.catalog()}}
  end

  def call("projects.list", _args) do
    projects = Enum.map(Projects.list_projects(), &project_summary/1)
    {:ok, projects_list_payload(projects)}
  end

  def call("projects.settings", %{"slug" => slug}) do
    with {:ok, project} <- ToolSupport.fetch_project(slug) do
      {:ok, project_settings_payload(project)}
    else
      {:error, reason} -> {:error, "project settings failed: #{inspect(reason)}"}
    end
  end

  def call("projects.tree", %{"slug" => slug}) do
    with {:ok, project} <- ToolSupport.fetch_project(slug) do
      {:ok, projects_tree_payload(slug, Projects.list_source_tree(project))}
    end
  end

  def call("projects.graph", _args) do
    projects =
      Projects.list_projects()
      |> Enum.map(&project_graph_entry/1)

    {:ok, projects_graph_payload(projects)}
  end

  def call("projects.create", %{"name" => name, "slug" => slug} = args) do
    attrs =
      %{
        "name" => name,
        "slug" => slug
      }
      |> ToolSupport.put_opt_map("target_type", Map.get(args, "target_type"))
      |> ToolSupport.put_opt_map("template", Map.get(args, "template"))

    case Projects.create_project(attrs) do
      {:ok, project} ->
        {:ok, project_create_payload(project)}

      {:error, reason} ->
        template = Map.get(args, "template", "starter")

        {:error,
         "project create failed: #{BootstrapError.describe(reason, %{template: template, operation: :create})}"}
    end
  end

  def call("projects.update_settings", %{"slug" => slug} = args) do
    with {:ok, project} <- ToolSupport.fetch_project(slug),
         {:ok, attrs} <- project_settings_update_attrs(project, args),
         {:ok, updated} <- Projects.update_project(project, attrs) do
      {:ok, project_settings_payload(updated)}
    else
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, reason} -> {:error, "project settings update failed: #{inspect(reason)}"}
    end
  end

  def call("projects.delete", %{"slug" => slug}) do
    with {:ok, project} <- ToolSupport.fetch_project(slug),
         {:ok, _deleted} <- Projects.delete_project(project) do
      {:ok, projects_delete_payload(slug)}
    else
      {:error, reason} -> {:error, "project delete failed: #{inspect(reason)}"}
    end
  end

  def call("projects.diff", %{"slug" => slug} = args) do
    with {:ok, project} <- ToolSupport.fetch_project(slug) do
      workspace = Projects.project_workspace_path(project)
      limit_bytes = args |> Map.get("limit_bytes", 50_000) |> parse_diff_limit()

      case System.cmd("git", ["-C", workspace, "diff", "--", "."], stderr_to_stdout: true) do
        {output, exit_code} ->
          truncated? = byte_size(output) > limit_bytes

          {:ok,
           %{
             slug: slug,
             workspace_path: workspace,
             exit_code: exit_code,
             truncated: truncated?,
             diff: binary_part(output, 0, min(byte_size(output), limit_bytes))
           }}
      end
    else
      {:error, reason} -> {:error, "project diff failed: #{inspect(reason)}"}
    end
  end

  def call("files.read", %{
        "slug" => slug,
        "source_root" => source_root,
        "rel_path" => rel_path
      }) do
    with {:ok, project} <- ToolSupport.fetch_project(slug),
         {:ok, content} <- Projects.read_source_file(project, source_root, rel_path) do
      {:ok, files_read_payload(slug, source_root, rel_path, content)}
    else
      {:error, reason} -> {:error, "read failed: #{inspect(reason)}"}
    end
  end

  def call("files.stat", %{
        "slug" => slug,
        "source_root" => source_root,
        "rel_path" => rel_path
      }) do
    with {:ok, project} <- ToolSupport.fetch_project(slug),
         {:ok, absolute_path} <- project_source_file_path(project, source_root, rel_path),
         {:ok, stat} <- File.stat(absolute_path),
         {:ok, content} <- File.read(absolute_path) do
      {:ok,
       %{
         slug: slug,
         source_root: source_root,
         rel_path: rel_path,
         bytes: stat.size,
         mtime: format_file_mtime(stat.mtime),
         sha256: sha256_hex(content)
       }}
    else
      {:error, reason} -> {:error, "stat failed: #{inspect(reason)}"}
    end
  end

  def call("files.read_range", %{
        "slug" => slug,
        "source_root" => source_root,
        "rel_path" => rel_path,
        "offset" => offset,
        "limit" => limit
      }) do
    with {:ok, project} <- ToolSupport.fetch_project(slug),
         {:ok, content} <- Projects.read_source_file(project, source_root, rel_path) do
      lines = String.split(content, "\n")
      offset = max(offset, 1)
      limit = ToolSupport.clamp_limit(limit)

      selected =
        lines
        |> Enum.drop(offset - 1)
        |> Enum.take(limit)
        |> Enum.with_index(offset)
        |> Enum.map(fn {line, line_number} -> %{line: line_number, text: line} end)

      {:ok,
       %{
         slug: slug,
         source_root: source_root,
         rel_path: rel_path,
         offset: offset,
         limit: limit,
         total_lines: length(lines),
         lines: selected
       }}
    else
      {:error, reason} -> {:error, "read range failed: #{inspect(reason)}"}
    end
  end

  def call("files.search", %{"slug" => slug, "query" => query} = args)
      when is_binary(query) do
    with {:ok, project} <- ToolSupport.fetch_project(slug),
         {:ok, roots} <- search_source_roots(project, Map.get(args, "source_root")) do
      limit = args |> Map.get("limit", 50) |> ToolSupport.parse_limit()

      matches =
        roots
        |> Enum.flat_map(&search_source_root(project, &1, query))
        |> Enum.take(limit)

      {:ok,
       %{
         slug: slug,
         query: query,
         count: length(matches),
         matches: matches
       }}
    else
      {:error, reason} -> {:error, "search failed: #{inspect(reason)}"}
    end
  end

  def call(
        "files.write",
        %{
          "slug" => slug,
          "source_root" => source_root,
          "rel_path" => rel_path,
          "content" => content
        }
      ) do
    with {:ok, project} <- ToolSupport.fetch_project(slug),
         :ok <- Projects.write_source_file(project, source_root, rel_path, content) do
      {:ok, files_write_payload(slug, source_root, rel_path)}
    else
      {:error, reason} -> {:error, "write failed: #{inspect(reason)}"}
    end
  end

  def call(
        "files.patch",
        %{
          "slug" => slug,
          "source_root" => source_root,
          "rel_path" => rel_path,
          "old_string" => old_string,
          "new_string" => new_string
        } = args
      ) do
    with {:ok, project} <- ToolSupport.fetch_project(slug),
         {:ok, current} <- Projects.read_source_file(project, source_root, rel_path),
         :ok <- validate_expected_sha256(current, Map.get(args, "expected_sha256")),
         {:ok, patched} <- replace_once(current, old_string, new_string),
         :ok <- Projects.write_source_file(project, source_root, rel_path, patched) do
      {:ok,
       files_patch_payload(slug, source_root, rel_path, sha256_hex(current), sha256_hex(patched))}
    else
      {:error, reason} -> {:error, "patch failed: #{inspect(reason)}"}
    end
  end

  @spec files_patch_payload(
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t()
        ) :: ToolTypes.files_patch_result()
  defp files_patch_payload(slug, source_root, rel_path, old_sha256, new_sha256) do
    %{
      saved: true,
      slug: slug,
      source_root: source_root,
      rel_path: rel_path,
      old_sha256: old_sha256,
      new_sha256: new_sha256
    }
  end

  @spec files_read_payload(String.t(), String.t(), String.t(), binary()) ::
          ToolTypes.files_read_result()
  defp files_read_payload(slug, source_root, rel_path, content) do
    %{slug: slug, source_root: source_root, rel_path: rel_path, content: content}
  end

  @spec files_write_payload(String.t(), String.t(), String.t()) :: ToolTypes.files_write_result()
  defp files_write_payload(slug, source_root, rel_path) do
    %{saved: true, slug: slug, source_root: source_root, rel_path: rel_path}
  end

  @spec project_create_payload(Ide.Projects.Project.t()) :: ToolTypes.project_create_result()
  defp project_create_payload(%Ide.Projects.Project{} = project), do: project_summary(project)

  @spec project_graph_entry(Ide.Projects.Project.t()) :: ToolTypes.project_graph_entry()
  defp project_graph_entry(%Ide.Projects.Project{} = project) do
    tree = Projects.list_source_tree(project)

    %{
      name: project.name,
      slug: project.slug,
      target_type: project.target_type,
      active: project.active,
      source_roots: project.source_roots,
      workspace_path: Projects.project_workspace_path(project),
      file_count: count_files(tree)
    }
  end

  @spec project_summary(Ide.Projects.Project.t()) :: ToolTypes.project_summary()
  defp project_summary(%Ide.Projects.Project{} = project) do
    %{
      name: project.name,
      slug: project.slug,
      target_type: project.target_type,
      source_roots: project.source_roots,
      active: project.active
    }
  end

  @spec projects_graph_payload([ToolTypes.project_graph_entry()]) ::
          ToolTypes.projects_graph_result()
  defp projects_graph_payload(projects), do: %{projects: projects}

  @spec projects_list_payload([ToolTypes.project_summary()]) :: ToolTypes.projects_list_result()
  defp projects_list_payload(projects), do: %{projects: projects}

  @spec projects_delete_payload(String.t()) :: ToolTypes.slug_ok_result()
  defp projects_delete_payload(slug), do: %{slug: slug, deleted: true}

  @spec projects_tree_payload(String.t(), Ide.Projects.Types.source_tree()) ::
          ToolTypes.projects_tree_result()
  defp projects_tree_payload(slug, tree) do
    %{slug: slug, tree: tree}
  end

  @spec count_files([map()]) :: non_neg_integer()
  defp count_files(nodes) when is_list(nodes) do
    Enum.reduce(nodes, 0, fn node, acc ->
      children = Map.get(node, :children, [])
      is_dir = Map.get(node, :type) == :dir

      if is_dir do
        acc + count_files(children)
      else
        acc + 1
      end
    end)
  end

  @spec maybe_put_existing(map(), map(), String.t()) :: map()
  defp maybe_put_existing(acc, source, key) when is_map(source) do
    case ToolSupport.map_value(source, key) do
      nil -> acc
      value -> Map.put(acc, key, value)
    end
  end

  @spec maybe_put_string_setting(map(), map(), String.t()) :: map()
  defp maybe_put_string_setting(acc, source, key) when is_map(source) do
    case ToolSupport.map_value(source, key) do
      value when is_binary(value) -> Map.put(acc, key, String.trim(value))
      _ -> acc
    end
  end

  @spec maybe_put_string_list_setting(map(), map(), String.t()) :: map()
  defp maybe_put_string_list_setting(acc, source, key) when is_map(source) do
    case ToolSupport.map_value(source, key) do
      values when is_list(values) ->
        values =
          values
          |> Enum.filter(&is_binary/1)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        Map.put(acc, key, values)

      _ ->
        acc
    end
  end

  @spec maybe_put_boolean_setting(map(), map(), String.t()) :: map()
  defp maybe_put_boolean_setting(acc, source, key) when is_map(source) do
    case ToolSupport.map_value(source, key) do
      nil -> acc
      value -> Map.put(acc, key, ToolSupport.normalize_mcp_boolean(value, false))
    end
  end

  @spec maybe_put_inclusion_setting(map(), map(), String.t(), [String.t()]) :: map()
  defp maybe_put_inclusion_setting(acc, source, key, allowed) when is_map(source) do
    case ToolSupport.map_value(source, key) do
      value when is_binary(value) ->
        value = String.trim(value)

        if value in allowed do
          Map.put(acc, key, value)
        else
          acc
        end

      _ ->
        acc
    end
  end

  @spec project_settings_payload(Ide.Projects.Project.t()) :: ToolTypes.projects_settings_result()
  defp project_settings_payload(%Ide.Projects.Project{} = project) do
    %{
      name: Map.get(project, :name),
      slug: Map.get(project, :slug),
      target_type: Map.get(project, :target_type),
      source_roots: Map.get(project, :source_roots) || [],
      active: Map.get(project, :active) == true,
      release_defaults: Map.get(project, :release_defaults) || %{},
      github: safe_github_settings(Map.get(project, :github) || %{}),
      debugger: safe_debugger_settings(Map.get(project, :debugger_settings) || %{})
    }
  end

  @spec project_settings_update_attrs(map(), map()) :: {:ok, map()} | {:error, String.t()}
  defp project_settings_update_attrs(project, args) when is_map(project) and is_map(args) do
    attrs =
      %{}
      |> maybe_put_string_setting(args, "name")
      |> maybe_put_inclusion_setting(args, "target_type", ~w(app watchface companion))
      |> maybe_put_boolean_setting(args, "active")

    attrs =
      case ToolSupport.map_value(args, "release_defaults") do
        release_defaults when is_map(release_defaults) ->
          current = Map.get(project, :release_defaults) || %{}

          Map.put(
            attrs,
            "release_defaults",
            Map.merge(current, safe_release_defaults(release_defaults))
          )

        _ ->
          attrs
      end

    attrs =
      case ToolSupport.map_value(args, "github") do
        github when is_map(github) ->
          current = Map.get(project, :github) || %{}
          Map.put(attrs, "github", Map.merge(current, safe_github_settings(github)))

        _ ->
          attrs
      end

    attrs =
      case ToolSupport.map_value(args, "debugger") do
        debugger when is_map(debugger) ->
          settings =
            (Map.get(project, :debugger_settings) || %{})
            |> Map.merge(safe_debugger_settings_update(debugger))

          Map.put(attrs, "debugger_settings", settings)

        _ ->
          attrs
      end

    {:ok, attrs}
  end

  @spec safe_release_defaults(map()) :: map()
  defp safe_release_defaults(map) when is_map(map) do
    %{}
    |> maybe_put_string_setting(map, "version_label")
    |> maybe_put_string_setting(map, "tags")
    |> maybe_put_string_list_setting(map, "target_platforms")
    |> maybe_put_string_list_setting(map, "capabilities")
  end

  @spec safe_github_settings(map()) :: map()
  defp safe_github_settings(map) when is_map(map) do
    visibility =
      map
      |> Map.get("visibility", Map.get(map, :visibility))
      |> then(fn
        "public" -> "public"
        _ -> nil
      end)

    github =
      %{}
      |> maybe_put_string_setting(map, "owner")
      |> maybe_put_string_setting(map, "repo")
      |> maybe_put_string_setting(map, "branch")

    case visibility do
      nil -> github
      v -> Map.put(github, "visibility", v)
    end
  end

  defp safe_github_settings(_), do: %{}

  @spec safe_debugger_settings(map()) :: map()
  defp safe_debugger_settings(map) when is_map(map) do
    %{}
    |> maybe_put_existing(map, "timeline_mode")
    |> maybe_put_existing(map, "watch_profile_id")
    |> maybe_put_existing(map, "emulator_target")
    |> maybe_put_existing(map, "emulator_mode")
    |> maybe_put_existing(map, "configuration_values")
    |> maybe_put_existing(map, "auto_fire")
    |> maybe_put_existing(map, "auto_fire_subscriptions")
    |> maybe_put_existing(map, "disabled_subscriptions")
    |> Map.put(
      "simulator",
      ToolSupport.normalize_mcp_simulator_settings(ToolSupport.map_value(map, "simulator") || %{})
    )
  end

  defp safe_debugger_settings(_), do: %{"simulator" => Debugger.default_simulator_settings()}

  @spec safe_debugger_settings_update(map()) :: map()
  defp safe_debugger_settings_update(map) when is_map(map) do
    %{}
    |> maybe_put_inclusion_setting(map, "timeline_mode", ~w(watch companion mixed separate))
    |> maybe_put_string_setting(map, "watch_profile_id")
    |> maybe_put_string_setting(map, "emulator_target")
    |> maybe_put_inclusion_setting(map, "emulator_mode", EmulatorSupport.allowed_mode_ids())
  end

  @spec project_source_file_path(map(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, atom()}
  defp project_source_file_path(project, source_root, rel_path)
       when is_binary(source_root) and is_binary(rel_path) do
    if source_root in project.source_roots do
      source_base = Path.join(Projects.project_workspace_path(project), source_root)
      expanded = Path.expand(rel_path, source_base)
      allowed_prefix = source_base <> "/"

      cond do
        expanded == source_base -> {:error, :invalid_path}
        String.starts_with?(expanded, allowed_prefix) -> {:ok, expanded}
        true -> {:error, :invalid_path}
      end
    else
      {:error, :invalid_source_root}
    end
  end

  defp project_source_file_path(_project, _source_root, _rel_path), do: {:error, :invalid_path}

  @spec format_file_mtime(:calendar.datetime()) :: String.t()
  defp format_file_mtime(mtime) do
    case NaiveDateTime.from_erl(mtime) do
      {:ok, ndt} -> NaiveDateTime.to_string(ndt)
      _ -> "unknown"
    end
  end

  @spec sha256_hex(binary()) :: String.t()
  defp sha256_hex(content), do: Base.encode16(:crypto.hash(:sha256, content), case: :lower)

  @spec validate_expected_sha256(binary(), WireTypes.sha256_input()) :: :ok | {:error, atom()}
  defp validate_expected_sha256(_content, nil), do: :ok
  defp validate_expected_sha256(_content, ""), do: :ok

  defp validate_expected_sha256(content, expected) when is_binary(expected) do
    if sha256_hex(content) == String.downcase(expected) do
      :ok
    else
      {:error, :stale_file}
    end
  end

  defp validate_expected_sha256(_content, _expected), do: {:error, :invalid_expected_sha256}

  @spec replace_once(binary(), binary(), binary()) :: {:ok, binary()} | {:error, atom()}
  defp replace_once(_content, "", _new_string), do: {:error, :empty_old_string}

  defp replace_once(content, old_string, new_string)
       when is_binary(old_string) and is_binary(new_string) do
    case :binary.matches(content, old_string) do
      [] -> {:error, :old_string_not_found}
      [_match] -> {:ok, String.replace(content, old_string, new_string, global: false)}
      _many -> {:error, :old_string_not_unique}
    end
  end

  defp replace_once(_content, _old_string, _new_string), do: {:error, :invalid_patch}

  @spec search_source_roots(map(), WireTypes.json_value()) ::
          {:ok, [String.t()]} | {:error, atom()}
  defp search_source_roots(project, nil), do: {:ok, project.source_roots}
  defp search_source_roots(project, ""), do: {:ok, project.source_roots}

  defp search_source_roots(project, source_root) when is_binary(source_root) do
    if source_root in project.source_roots do
      {:ok, [source_root]}
    else
      {:error, :invalid_source_root}
    end
  end

  defp search_source_roots(_project, _source_root), do: {:error, :invalid_source_root}

  @spec search_source_root(map(), String.t(), String.t()) :: [map()]
  defp search_source_root(_project, _source_root, ""), do: []

  defp search_source_root(project, source_root, query) do
    project
    |> Projects.list_source_tree()
    |> Enum.find_value([], fn
      %{source_root: ^source_root, nodes: nodes} -> nodes
      _ -> nil
    end)
    |> flatten_tree_files()
    |> Enum.flat_map(fn rel_path ->
      case Projects.read_source_file(project, source_root, rel_path) do
        {:ok, content} -> search_file_content(source_root, rel_path, content, query)
        {:error, _reason} -> []
      end
    end)
  end

  @spec flatten_tree_files([map()]) :: [String.t()]
  defp flatten_tree_files(nodes) when is_list(nodes) do
    Enum.flat_map(nodes, fn
      %{type: :file, rel_path: rel_path} -> [rel_path]
      %{type: :dir, children: children} -> flatten_tree_files(children)
      %{"type" => :file, "rel_path" => rel_path} -> [rel_path]
      %{"type" => :dir, "children" => children} -> flatten_tree_files(children)
      _ -> []
    end)
  end

  @spec search_file_content(String.t(), String.t(), binary(), String.t()) :: [map()]
  defp search_file_content(source_root, rel_path, content, query) do
    content
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_number} ->
      if String.contains?(line, query) do
        [%{source_root: source_root, rel_path: rel_path, line: line_number, text: line}]
      else
        []
      end
    end)
  end

  @spec parse_diff_limit(WireTypes.limit_input()) :: pos_integer()
  defp parse_diff_limit(value) when is_integer(value), do: value |> max(1) |> min(200_000)

  defp parse_diff_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _} -> parse_diff_limit(parsed)
      _ -> 50_000
    end
  end

  defp parse_diff_limit(_value), do: 50_000
end
