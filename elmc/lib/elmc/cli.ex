defmodule Elmc.CLI do
  @moduledoc """
  Command-line entrypoint for the compiler.
  """

  alias ElmEx.DiagnosticFormatter
  @blocked_package_families ~w(elm/core elm/browser elm/bytes elm/file elm/html elm/http)

  @spec main([String.t()]) :: no_return() | :ok
  def main(argv) do
    case argv do
      ["check", project_dir] ->
        run_check(project_dir)

      ["compile", project_dir, "--out-dir", out_dir] ->
        run_compile(project_dir, out_dir, true)

      ["compile", project_dir, "--out-dir", out_dir, "--no-strip-dead-code"] ->
        run_compile(project_dir, out_dir, false)

      ["manifest", project_dir] ->
        run_manifest(project_dir)

      _ ->
        print_help()
    end
  end

  @spec run_check(String.t()) :: :ok
  defp run_check(project_dir) do
    case Elmc.check(project_dir) do
      {:ok, project} ->
        IO.puts("check: ok")
        IO.puts("modules: #{length(project.modules)}")
        print_warnings(project.diagnostics)

      {:error, error} ->
        IO.puts(:stderr, "check: failed")
        IO.puts(:stderr, DiagnosticFormatter.format_error(error))
        System.halt(1)
    end
  end

  @spec run_compile(String.t(), String.t() | nil, boolean()) :: :ok
  defp run_compile(project_dir, out_dir, strip_dead_code) do
    case Elmc.compile(project_dir, %{out_dir: out_dir, strip_dead_code: strip_dead_code}) do
      {:ok, result} ->
        IO.puts("compile: ok")
        IO.puts("output: #{out_dir}")
        print_warnings(compile_warnings(result))

      {:error, error} ->
        IO.puts(:stderr, "compile: failed")
        IO.puts(:stderr, DiagnosticFormatter.format_error(error))
        System.halt(1)
    end
  end

  @spec run_manifest(String.t()) :: :ok
  defp run_manifest(project_dir) do
    case Elmc.check(project_dir) do
      {:ok, project} ->
        dependencies = load_declared_dependencies(project_dir)
        compatibility = dependency_compatibility_rows(dependencies)

        {supported_packages, excluded_packages} =
          compatibility
          |> Enum.reduce({[], []}, fn row, {supported, excluded} ->
            case row["status"] do
              "blocked" -> {supported, [row["package"] | excluded]}
              _ -> {[row["package"] | supported], excluded}
            end
          end)
          |> then(fn {supported, excluded} ->
            {Enum.uniq(Enum.reverse(supported)), Enum.uniq(Enum.reverse(excluded))}
          end)

        manifest = %{
          supported_packages: supported_packages,
          excluded_packages: excluded_packages,
          modules_detected: Enum.map(project.modules, & &1.name),
          dependency_compatibility: compatibility
        }

        IO.puts(Jason.encode!(manifest, pretty: true))

      {:error, error} ->
        IO.puts(:stderr, "manifest: failed")
        IO.puts(:stderr, DiagnosticFormatter.format_error(error))
        System.halt(1)
    end
  end

  @spec print_help() :: :ok
  defp print_help do
    IO.puts("""
    elmc usage:
      elmc check <project_dir>
      elmc compile <project_dir> --out-dir <dir>
      elmc compile <project_dir> --out-dir <dir> --no-strip-dead-code
      elmc manifest <project_dir>
    """)
  end

  @spec compile_warnings(%{project: ElmEx.Frontend.Project.t(), ir: ElmEx.IR.t()}) :: [map()]
  defp compile_warnings(%{project: project, ir: ir}) do
    project_warnings = Map.get(project, :diagnostics, [])

    ir_warnings =
      ir
      |> Map.get(:diagnostics, [])
      |> Enum.map(fn warning ->
        %{
          "type" => "lowerer-warning",
          "source" => Map.get(warning, :source, "lowerer"),
          "module" => Map.get(warning, :module),
          "function" => Map.get(warning, :function),
          "message" => Map.get(warning, :message, inspect(warning)),
          "severity" => Map.get(warning, :severity, "warning")
        }
      end)

    dedupe_warnings(project_warnings ++ ir_warnings)
  end

  @spec print_warnings([map()]) :: :ok
  defp print_warnings(warnings) when is_list(warnings) do
    rendered = DiagnosticFormatter.format_warnings(warnings)

    if rendered != "" do
      IO.puts(:stderr, rendered)
    end

    if warnings != [] and warnings_json_enabled?() do
      IO.puts(:stderr, "ELMC_WARNINGS_JSON:" <> Jason.encode!(warnings))
    end
  end

  @spec dedupe_warnings([map()]) :: [map()]
  defp dedupe_warnings(warnings) do
    warnings
    |> Enum.reduce({MapSet.new(), []}, fn warning, {seen, acc} ->
      key = warning_dedupe_key(warning)

      if MapSet.member?(seen, key) do
        {seen, acc}
      else
        {MapSet.put(seen, key), [warning | acc]}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  @spec warning_dedupe_key(term()) :: term()
  defp warning_dedupe_key(warning) when is_map(warning) do
    {
      Map.get(warning, "type", Map.get(warning, :type, "warning")),
      Map.get(warning, "code", Map.get(warning, :code)),
      Map.get(warning, "source", Map.get(warning, :source, "unknown")),
      Map.get(warning, "module", Map.get(warning, :module)),
      Map.get(warning, "function", Map.get(warning, :function)),
      Map.get(warning, "line", Map.get(warning, :line)),
      Map.get(warning, "constructor", Map.get(warning, :constructor)),
      Map.get(warning, "expected_kind", Map.get(warning, :expected_kind)),
      Map.get(warning, "has_arg_pattern", Map.get(warning, :has_arg_pattern)),
      Map.get(warning, "message", Map.get(warning, :message))
    }
  end

  defp warning_dedupe_key(other), do: {:unknown, inspect(other)}

  @spec warnings_json_enabled?() :: boolean()
  defp warnings_json_enabled? do
    case System.get_env("ELMC_WARNINGS_JSON") do
      value when value in ["1", "true", "TRUE", "yes", "YES"] -> true
      _ -> false
    end
  end

  @spec load_declared_dependencies(String.t()) :: [String.t()]
  defp load_declared_dependencies(project_dir) when is_binary(project_dir) do
    elm_json = Path.join(project_dir, "elm.json")

    with true <- File.exists?(elm_json),
         {:ok, content} <- File.read(elm_json),
         {:ok, decoded} <- Jason.decode(content),
         deps when is_map(deps) <- Map.get(decoded, "dependencies", %{}) do
      direct = deps |> Map.get("direct", %{}) |> dependency_keys()
      indirect = deps |> Map.get("indirect", %{}) |> dependency_keys()
      Enum.uniq(direct ++ indirect)
    else
      _ -> []
    end
  end

  @spec dependency_keys(term()) :: term()
  defp dependency_keys(map) when is_map(map), do: Map.keys(map)
  defp dependency_keys(_), do: []

  @spec dependency_compatibility_rows([String.t()]) :: [map()]
  defp dependency_compatibility_rows(packages) when is_list(packages) do
    packages
    |> Enum.filter(&is_binary/1)
    |> Enum.sort()
    |> Enum.map(fn package ->
      if package in @blocked_package_families do
        %{
          "package" => package,
          "status" => "blocked",
          "reason_code" => "blocked_runtime_family",
          "message" =>
            "Dependency #{package} is currently blocked for Pebble runtime compatibility."
        }
      else
        %{
          "package" => package,
          "status" => "supported",
          "reason_code" => "allowed",
          "message" => "Dependency #{package} is currently allowed."
        }
      end
    end)
  end
end
