defmodule ElmEx.Frontend.Bridge do
  @moduledoc """
  Frontend bridge that reuses Elm tooling for typechecking/diagnostics while
  producing compiler-friendly metadata for code generation.
  """

  alias ElmEx.Frontend.Project
  alias ElmEx.IR.Lowerer

  @spec load_project(String.t()) :: {:ok, Project.t()} | {:error, map()}
  def load_project(project_dir) do
    project_dir = Path.expand(project_dir)

    with {:ok, elm_json} <- read_elm_json(project_dir),
         {:ok, module_paths} <- discover_module_paths(project_dir, elm_json),
         {:ok, diagnostics} <- run_elm_check(project_dir, module_paths),
         {:ok, modules} <- load_modules(module_paths) do
      {:ok,
       %Project{
         project_dir: project_dir,
         elm_json: elm_json,
         modules: modules,
         diagnostics: diagnostics
       }
       |> attach_lowerer_diagnostics()}
    end
  end

  @spec read_elm_json(String.t()) :: {:ok, map()} | {:error, map()}
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

  @spec run_elm_check(String.t(), [String.t()]) :: {:ok, [map()]} | {:error, map()}
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

  @spec run_elm_make_check(String.t(), [String.t()]) :: {:ok, [map()]} | {:error, map()}
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

  @spec parse_diagnostics(String.t()) :: [map()]
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

  @spec discover_module_paths(String.t(), map()) :: {:ok, [String.t()]} | {:error, map()}
  defp discover_module_paths(project_dir, elm_json) do
    source_dirs =
      Map.get(elm_json, "source-directories", ["src"]) ++ builtin_source_dirs(elm_json)

    module_paths =
      source_dirs
      |> Enum.flat_map(fn dir ->
        source_root =
          case Path.type(dir) do
            :absolute -> dir
            _ -> Path.join(project_dir, dir)
          end

        Path.wildcard(Path.join([source_root, "**", "*.elm"]))
      end)
      |> Enum.uniq()

    {:ok, module_paths}
  end

  @spec builtin_source_dirs(map()) :: [String.t()]
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

  defp builtin_source_dirs(_), do: []

  @spec dependency_names(term()) :: [String.t()]
  defp dependency_names(%{"direct" => direct, "indirect" => indirect}) do
    dependency_names(direct) ++ dependency_names(indirect)
  end

  defp dependency_names(deps) when is_map(deps), do: Map.keys(deps)
  defp dependency_names(_), do: []

  @spec load_modules([String.t()]) :: {:ok, [ElmEx.Frontend.Module.t()]} | {:error, map()}
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

  @spec attach_lowerer_diagnostics(ElmEx.Frontend.Project.t()) :: ElmEx.Frontend.Project.t()
  defp attach_lowerer_diagnostics(%Project{} = project) do
    {:ok, ir} = Lowerer.lower_project(project)

    lowerer_diagnostics =
      ir.diagnostics
      |> Enum.map(&bridge_lowerer_diagnostic/1)

    %{project | diagnostics: project.diagnostics ++ lowerer_diagnostics}
  end

  @spec bridge_lowerer_diagnostic(map()) :: map()
  defp bridge_lowerer_diagnostic(diagnostic) when is_map(diagnostic) do
    %{
      "type" => "lowerer-warning",
      "source" => Map.get(diagnostic, :source, "lowerer"),
      "code" => Map.get(diagnostic, :code),
      "module" => Map.get(diagnostic, :module),
      "function" => Map.get(diagnostic, :function),
      "line" => Map.get(diagnostic, :line),
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
