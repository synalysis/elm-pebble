defmodule ElmEx.Frontend.Bridge do
  @moduledoc """
  Frontend bridge that reuses Elm tooling for typechecking/diagnostics while
  producing compiler-friendly metadata for code generation.
  """

  alias ElmEx.Frontend.Bridge.Types, as: BridgeTypes
  alias ElmEx.Frontend.Project
  alias ElmEx.IR.Lowerer
  alias ElmEx.IR.Types.Diagnostic, as: IRDiagnostic
  alias ElmEx.Types

  @spec load_project(String.t()) :: {:ok, Project.t()} | {:error, BridgeTypes.bridge_error()}
  def load_project(project_dir) do
    load_project_from_sources(project_dir, %{})
  end

  @doc """
  Loads a project from disk, optionally overlaying module sources from memory.

  `source_overrides` keys are paths relative to `project_dir` (for example `"src/Main.elm"`).
  """
  @spec load_project_from_sources(String.t(), %{String.t() => String.t()}) ::
          {:ok, Project.t()} | {:error, BridgeTypes.bridge_error()}
  def load_project_from_sources(project_dir, source_overrides \\ %{})
      when is_binary(project_dir) and is_map(source_overrides) do
    project_dir = Path.expand(project_dir)

    with {:ok, elm_json} <- read_elm_json(project_dir),
         {:ok, module_paths} <- discover_module_paths(project_dir, elm_json),
         {:ok, diagnostics} <- run_elm_check(project_dir, module_paths),
         {:ok, modules} <- load_modules(module_paths),
         {:ok, modules} <- apply_source_overrides(project_dir, modules, source_overrides) do
      modules = disambiguate_package_module_collisions(modules)

      {:ok,
       %Project{
         project_dir: project_dir,
         elm_json: elm_json,
         modules: modules,
         diagnostics: diagnostics
       }
       |> attach_missing_import_diagnostics()
       |> attach_lowerer_diagnostics()}
    end
  end

  @spec apply_source_overrides(String.t(), [ElmEx.Frontend.Module.t()], %{
          String.t() => String.t()
        }) ::
          {:ok, [ElmEx.Frontend.Module.t()]} | {:error, BridgeTypes.parse_error()}
  defp apply_source_overrides(_project_dir, modules, overrides)
       when map_size(overrides) == 0,
       do: {:ok, modules}

  defp apply_source_overrides(project_dir, modules, overrides) do
    Enum.reduce_while(modules, {:ok, []}, fn mod, {:ok, acc} ->
      rel_path = Path.relative_to(mod.path, project_dir)

      case Map.get(overrides, rel_path) do
        source when is_binary(source) ->
          case ElmEx.Frontend.GeneratedParser.parse_source(rel_path, source) do
            {:ok, parsed} -> {:cont, {:ok, [parsed | acc]}}
            {:error, reason} -> {:halt, {:error, Map.put(reason, :path, rel_path)}}
          end

        _ ->
          {:cont, {:ok, [mod | acc]}}
      end
    end)
    |> case do
      {:ok, mods} -> {:ok, Enum.reverse(mods)}
      other -> other
    end
  end

  @spec read_elm_json(String.t()) :: {:ok, Types.elm_json()} | {:error, BridgeTypes.config_error()}
  defp read_elm_json(project_dir) do
    elm_json_path = Path.join(project_dir, "elm.json")

    with {:ok, content} <- File.read(elm_json_path),
         {:ok, parsed} <- Jason.decode(content) do
      {:ok, parsed}
    else
      {:error, :enoent} ->
        {:error, %{kind: :config_error, reason: :missing_elm_json, path: elm_json_path}}

      {:error, reason} ->
        {:error, %{kind: :config_error, reason: reason}}
    end
  end

  @spec run_elm_check(String.t(), [String.t()]) ::
          {:ok, [Types.elm_report()]} | {:error, BridgeTypes.elm_check_failed()}
  defp run_elm_check(_project_dir, []), do: {:ok, []}

  defp run_elm_check(project_dir, module_paths) do
    if elm_make_check_enabled?() do
      run_elm_make_check(project_dir, module_paths)
    else
      # Skip external elm checker by default to avoid network/package side-effects
      # during elmc frontend loading; parser/lowerer diagnostics still run.
      {:ok, []}
    end
  end

  @spec run_elm_make_check(String.t(), [String.t()]) ::
          {:ok, [Types.elm_report()]} | {:error, BridgeTypes.elm_check_failed()}
  defp run_elm_make_check(project_dir, module_paths) do
    entry =
      Enum.find(module_paths, fn path -> String.ends_with?(path, "Main.elm") end) ||
        hd(module_paths)

    entry_rel = Path.relative_to(entry, project_dir)
    command = "elm make #{entry_rel} --report=json --output=/tmp/elmc-check.js"

    {stdout, exit_code} =
      System.cmd("bash", ["-lc", command], cd: project_dir, stderr_to_stdout: true)

    diagnostics = parse_diagnostics(stdout)

    case exit_code do
      0 -> {:ok, diagnostics}
      _ -> {:error, %{kind: :elm_check_failed, diagnostics: diagnostics, raw: stdout}}
    end
  end

  @spec parse_diagnostics(String.t()) :: [Types.elm_report()]
  defp parse_diagnostics(stdout) do
    stdout
    |> String.split("\n", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != ""))
    |> Enum.flat_map(fn line ->
      case Jason.decode(line) do
        {:ok, payload} -> [payload]
        _ -> []
      end
    end)
  end

  @spec discover_module_paths(String.t(), Types.elm_json()) ::
          {:ok, [String.t()]} | {:error, BridgeTypes.bridge_error()}
  defp discover_module_paths(project_dir, elm_json) do
    source_dirs =
      Map.get(elm_json, "source-directories", ["src"]) ++
        builtin_source_dirs(elm_json) ++
        dependency_package_source_dirs(project_dir, elm_json)

    module_paths =
      source_dirs
      |> Enum.flat_map(fn dir ->
        source_root =
          case Path.type(dir) do
            :absolute -> dir
            _ -> Path.join(project_dir, dir)
          end

        source_root = Path.expand(source_root)

        source_root
        |> Path.join("**/*.elm")
        |> Path.wildcard()
        |> Enum.map(&{source_root, &1})
      end)
      |> unique_module_paths_by_source_order()

    {:ok, module_paths}
  end

  defp dependency_package_source_dirs(project_dir, elm_json)
       when is_binary(project_dir) and is_map(elm_json) do
    deps =
      elm_json
      |> Map.get("dependencies", %{})
      |> dependency_version_pairs()

    Enum.flat_map(deps, fn {pkg, ver} ->
      case String.split(pkg, "/", parts: 2) do
        [author, name] ->
          [
            Path.join([project_dir, "elm-stuff", "packages", author, name, ver, "src"]),
            Path.join([System.user_home!(), ".elm", "0.19.1", "packages", author, name, ver, "src"])
          ]
          |> Enum.map(&Path.expand/1)
          |> Enum.filter(&File.dir?/1)

        _ ->
          []
      end
    end)
  end

  defp dependency_package_source_dirs(_project_dir, _elm_json), do: []

  defp dependency_version_pairs(%{"direct" => direct, "indirect" => indirect})
       when is_map(direct) and is_map(indirect) do
    Map.merge(indirect, direct)
    |> Enum.filter(fn {k, v} -> is_binary(k) and is_binary(v) end)
  end

  defp dependency_version_pairs(_), do: []

  @spec unique_module_paths_by_source_order([{String.t(), String.t()}]) :: [String.t()]
  defp unique_module_paths_by_source_order(source_paths) do
    {_seen, paths} =
      Enum.reduce(source_paths, {MapSet.new(), []}, fn {source_root, path}, {seen, acc} ->
        module_name = module_name_from_source_path(source_root, path)
        # Official Elm resolves unexposed modules package-locally, so the same
        # Elm module name may exist in multiple packages (e.g. Pattern in
        # justinmimbs/date and dillonkearns/elm-pages). Key by package + name.
        # App source-directories still share one package id so overlays keep
        # first-wins behavior.
        key = {package_id_from_source_root(source_root), module_name}

        if MapSet.member?(seen, key) do
          {seen, acc}
        else
          {MapSet.put(seen, key), [path | acc]}
        end
      end)

    Enum.reverse(paths)
  end

  @doc false
  @spec package_id_from_source_root(String.t()) :: String.t()
  def package_id_from_source_root(source_root) when is_binary(source_root) do
    parts = Path.split(Path.expand(source_root))

    case Enum.find_index(parts, &(&1 == "packages")) do
      nil ->
        "app"

      idx ->
        case Enum.drop(parts, idx + 1) do
          [author, name, version | _]
          when is_binary(author) and is_binary(name) and is_binary(version) ->
            "#{author}/#{name}@#{version}"

          _ ->
            "app"
        end
    end
  end

  def package_id_from_source_root(_), do: "app"

  @doc false
  @spec package_id_from_path(String.t() | nil) :: String.t()
  def package_id_from_path(path) when is_binary(path) do
    parts = Path.split(Path.expand(path))

    case Enum.find_index(parts, &(&1 == "packages")) do
      nil ->
        "app"

      idx ->
        case Enum.drop(parts, idx + 1) do
          [author, name, version | _]
          when is_binary(author) and is_binary(name) and is_binary(version) ->
            "#{author}/#{name}@#{version}"

          _ ->
            "app"
        end
    end
  end

  def package_id_from_path(_), do: "app"

  # When multiple packages ship the same Elm module name, keep all of them under
  # stable IR names and rewrite same-package imports to the mangled target.
  @spec disambiguate_package_module_collisions([ElmEx.Frontend.Module.t()]) ::
          [ElmEx.Frontend.Module.t()]
  defp disambiguate_package_module_collisions(modules) when is_list(modules) do
    by_name = Enum.group_by(modules, & &1.name)

    collisions =
      by_name
      |> Enum.filter(fn {_name, group} -> length(group) > 1 end)
      |> Map.new(fn {name, group} ->
        by_pkg =
          Map.new(group, fn mod ->
            {package_id_from_path(mod.path), mangle_package_module_name(package_id_from_path(mod.path), name)}
          end)

        {name, by_pkg}
      end)

    if map_size(collisions) == 0 do
      modules
    else
      path_to_mangled =
        Enum.reduce(collisions, %{}, fn {elm_name, by_pkg}, acc ->
          Enum.reduce(by_pkg, acc, fn {pkg, mangled}, acc2 ->
            case Enum.find(modules, fn m -> m.name == elm_name and package_id_from_path(m.path) == pkg end) do
              %{path: path} -> Map.put(acc2, path, mangled)
              _ -> acc2
            end
          end)
        end)

      Enum.map(modules, fn mod ->
        elm_name = mod.name
        pkg = package_id_from_path(mod.path)
        new_name = Map.get(path_to_mangled, mod.path, elm_name)

        import_entries =
          Enum.map(mod.import_entries || [], fn entry ->
            rewrite_collision_import_entry(entry, pkg, collisions)
          end)

        imports =
          (mod.imports || [])
          |> Enum.map(fn imported ->
            case Map.get(collisions, imported) do
              %{^pkg => mangled} -> mangled
              _ -> imported
            end
          end)

        %{mod | name: new_name, imports: imports, import_entries: import_entries}
      end)
    end
  end

  defp disambiguate_package_module_collisions(modules), do: modules

  defp rewrite_collision_import_entry(entry, importer_pkg, collisions) when is_map(entry) do
    module_name = Map.get(entry, "module") || Map.get(entry, :module)

    case is_binary(module_name) and Map.get(collisions, module_name) do
      %{^importer_pkg => mangled} ->
        as_name = Map.get(entry, "as") || Map.get(entry, :as) || module_name

        entry
        |> Map.put("module", mangled)
        |> Map.put("as", as_name)
        |> Map.delete(:module)
        |> Map.delete(:as)

      _ ->
        entry
    end
  end

  defp rewrite_collision_import_entry(entry, _importer_pkg, _collisions), do: entry

  @doc false
  @spec mangle_package_module_name(String.t(), String.t()) :: String.t()
  def mangle_package_module_name(package_id, elm_name)
      when is_binary(package_id) and is_binary(elm_name) do
    pkg_part =
      package_id
      |> String.replace("@", "_")
      |> String.replace("/", "_")
      |> String.replace("-", "_")
      |> String.replace(".", "_")

    "Pkg." <> pkg_part <> "." <> elm_name
  end

  def mangle_package_module_name(_, elm_name) when is_binary(elm_name), do: elm_name

  @spec module_name_from_source_path(String.t(), String.t()) :: String.t()
  defp module_name_from_source_path(source_root, path) do
    path
    |> Path.expand()
    |> Path.relative_to(source_root)
    |> Path.rootname()
    |> Path.split()
    |> Enum.join(".")
  end

  @spec builtin_source_dirs(Types.elm_json()) :: [String.t()]
  defp builtin_source_dirs(elm_json) when is_map(elm_json) do
    deps =
      elm_json
      |> Map.get("dependencies", %{})
      |> dependency_names()

    if "elm/random" in deps do
      [Path.expand("../../../../ide/priv/internal_packages/elm-random/src", __DIR__)]
    else
      []
    end
  end

  @spec dependency_names(Types.dependency_sections() | Types.elm_json() | list() | nil) :: [String.t()]
  defp dependency_names(%{"direct" => direct, "indirect" => indirect}) do
    dependency_names(direct) ++ dependency_names(indirect)
  end

  defp dependency_names(deps) when is_map(deps), do: Map.keys(deps)
  defp dependency_names(_), do: []

  @spec load_modules([String.t()]) ::
          {:ok, [ElmEx.Frontend.Module.t()]} | {:error, BridgeTypes.parse_error()}
  defp load_modules(module_paths) do
    backend = parser_backend()

    modules =
      Enum.reduce_while(module_paths, {:ok, []}, fn path, {:ok, acc} ->
        case backend.parse_file(path) do
          {:ok, mod} -> {:cont, {:ok, [mod | acc]}}
          {:error, reason} -> {:halt, {:error, Map.put(reason, :path, path)}}
        end
      end)

    case modules do
      {:ok, mods} -> {:ok, Enum.reverse(mods)}
      {:error, _} = error -> error
    end
  end

  @spec parser_backend() :: module()
  defp parser_backend do
    backend =
      System.get_env("ELMEX_PARSER_BACKEND") ||
        to_string(Application.get_env(:elm_ex, :parser_backend, :generated))

    case backend do
      "generated" -> ElmEx.Frontend.GeneratedParserBackend
      "compat" -> ElmEx.Frontend.CompatParserBackend
      "legacy" -> ElmEx.Frontend.CompatParserBackend
      _ -> ElmEx.Frontend.GeneratedParserBackend
    end
  end

  @spec elm_make_check_enabled?() :: boolean()
  defp elm_make_check_enabled? do
    case System.get_env("ELMEX_ENABLE_ELM_MAKE_CHECK") do
      value when value in ["1", "true", "TRUE", "yes", "YES"] ->
        true

      value when value in ["0", "false", "FALSE", "no", "NO"] ->
        false

      _ ->
        Application.get_env(:elm_ex, :enable_elm_make_check, false)
    end
  end

  defp attach_missing_import_diagnostics(%Project{} = project) do
    available =
      project.modules
      |> Enum.map(& &1.name)
      |> MapSet.new()

    missing =
      project.modules
      |> Enum.filter(fn mod ->
        path = Map.get(mod, :path)
        is_binary(path) and String.starts_with?(path, project.project_dir <> "/")
      end)
      |> Enum.flat_map(fn mod ->
        (mod.imports || [])
        |> Enum.filter(&missing_import?/1)
        |> Enum.reject(&MapSet.member?(available, &1))
        |> Enum.map(fn imported ->
          %{
            "type" => "missing-import",
            "severity" => "error",
            "module" => mod.name,
            "import" => imported,
            "message" =>
              "Module #{mod.name} imports #{imported}, but it was not found in loaded sources. Add the dependency (or source directory) that provides #{imported}."
          }
        end)
      end)

    %{project | diagnostics: project.diagnostics ++ missing}
  end

  defp missing_import?(name) when is_binary(name) do
    name != "" and
      not String.starts_with?(name, "Elm.Kernel.") and
      not String.starts_with?(name, "Basics") and
      not String.starts_with?(name, "Debug") and
      not String.starts_with?(name, "List") and
      not String.starts_with?(name, "Maybe") and
      not String.starts_with?(name, "Result") and
      not String.starts_with?(name, "String") and
      not String.starts_with?(name, "Char") and
      not String.starts_with?(name, "Tuple") and
      not String.starts_with?(name, "Platform") and
      not String.starts_with?(name, "Dict") and
      not String.starts_with?(name, "Set") and
      not String.starts_with?(name, "Array") and
      not String.starts_with?(name, "Bitwise")
  end

  defp missing_import?(_), do: false

  @spec attach_lowerer_diagnostics(ElmEx.Frontend.Project.t()) :: ElmEx.Frontend.Project.t()
  defp attach_lowerer_diagnostics(%Project{} = project) do
    {:ok, ir} = Lowerer.lower_project(project)

    lowerer_diagnostics =
      ir.diagnostics
      |> Enum.map(&bridge_lowerer_diagnostic/1)

    %{project | diagnostics: project.diagnostics ++ lowerer_diagnostics}
  end

  @spec bridge_lowerer_diagnostic(IRDiagnostic.t()) :: BridgeTypes.lowerer_diagnostic()
  defp bridge_lowerer_diagnostic(diagnostic) when is_map(diagnostic) do
    %{
      "type" => "lowerer-warning",
      "source" => Map.get(diagnostic, :source, "lowerer"),
      "code" => Map.get(diagnostic, :code),
      "module" => Map.get(diagnostic, :module),
      "function" => Map.get(diagnostic, :function),
      "file" => Map.get(diagnostic, :file),
      "line" => Map.get(diagnostic, :line),
      "column" => Map.get(diagnostic, :column),
      "constructor" => Map.get(diagnostic, :constructor),
      "expected_kind" =>
        case Map.get(diagnostic, :expected_kind) do
          nil -> nil
          kind when is_atom(kind) -> Atom.to_string(kind)
          kind -> kind
        end,
      "has_arg_pattern" => Map.get(diagnostic, :has_arg_pattern),
      "message" => Map.get(diagnostic, :message, inspect(diagnostic)),
      "severity" => Map.get(diagnostic, :severity, "warning")
    }
  end
end
