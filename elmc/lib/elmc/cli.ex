defmodule Elmc.CLI do
  @moduledoc """
  Command-line entrypoint for the compiler.
  """

  alias ElmEx.DiagnosticFormatter
  alias Elmc.CLI.Types

  @blocked_package_families ~w(elm/core elm/browser elm/bytes elm/file elm/html elm/http)

  @type cli_diagnostic :: Types.cli_diagnostic()
  @type run_status :: Types.run_status()
  @type project_run :: Types.project_run()
  @type manifest_run :: Types.manifest_run()
  @type warning_dedupe_key ::
          {String.t(), String.t() | nil, String.t(), String.t() | nil, String.t() | nil,
           integer() | nil, String.t() | nil, String.t() | nil, boolean() | nil, String.t() | nil}
          | {:unknown, String.t()}

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
    case check_project(project_dir) do
      %{status: :ok, output: output} ->
        IO.write(output)
        :ok

      %{status: :error, output: output} ->
        IO.puts(:stderr, output)
        System.halt(1)
    end
  end

  @doc """
  Runs `elmc check` in-process and returns CLI-compatible output for IDE integration.
  """
  @spec check_project(String.t()) :: project_run()
  def check_project(project_dir) do
    case Elmc.check(project_dir) do
      {:ok, project} ->
        warnings = project |> Map.get(:diagnostics, []) |> dedupe_warnings()
        status = if error_diagnostics?(warnings), do: :error, else: :ok

        %{
          status: status,
          output: check_output(status, project, warnings),
          warnings: warnings
        }

      {:error, error} ->
        %{
          status: :error,
          output: "check: failed\n" <> DiagnosticFormatter.format_error(error),
          warnings: []
        }
    end
  end

  @spec check_output(run_status(), map(), [map()]) :: String.t()
  defp check_output(:ok, project, warnings) do
    [
      "check: ok",
      "modules: #{length(project.modules)}",
      warnings_output(warnings)
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp check_output(:error, project, warnings) do
    [
      "check: failed",
      "modules: #{length(project.modules)}",
      warnings_output(warnings)
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  @spec run_compile(String.t(), String.t() | nil, boolean()) :: :ok
  defp run_compile(project_dir, out_dir, strip_dead_code) do
    case compile_project(project_dir, out_dir, strip_dead_code: strip_dead_code) do
      %{status: :ok, output: output} ->
        IO.write(output)
        :ok

      %{status: :error, output: output} ->
        IO.puts(:stderr, output)
        System.halt(1)
    end
  end

  @doc """
  Runs `elmc compile` in-process and returns CLI-compatible output for IDE integration.

  Pass `elmc_opts:` to compile with Pebble production flags (runtime pruning, direct render).
  """
  @spec compile_project(String.t(), String.t(), keyword()) :: project_run()
  def compile_project(project_dir, out_dir, opts \\ []) do
    elmc_opts = elmc_opts_from_cli(out_dir, opts)

    project_dir
    |> compile_with_opts(elmc_opts)
    |> project_run_from_compile(out_dir)
  end

  @doc false
  @spec compile_with_opts(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def compile_with_opts(project_dir, opts) when is_binary(project_dir) and is_map(opts) do
    with {:ok, result} <- Elmc.compile(project_dir, opts),
         :ok <- validate_compile_result(result) do
      {:ok, result}
    else
      {:error, warnings} when is_list(warnings) ->
        {:error, {:compile_diagnostics, warnings}}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    exception in ArgumentError ->
      if direct_render_only_view_error?(exception, opts) do
        compile_with_opts(project_dir, Map.put(opts, :direct_render_only, false))
      else
        {:error, {:compiler_exception, exception.__struct__, Exception.message(exception)}}
      end

    exception ->
      {:error, {:compiler_exception, exception.__struct__, Exception.message(exception)}}
  catch
    kind, reason ->
      {:error, {:compiler_exception, kind, reason}}
  end

  defp elmc_opts_from_cli(out_dir, opts) do
    case Keyword.get(opts, :elmc_opts) do
      %{} = elmc_opts ->
        elmc_opts
        |> Map.put_new(:out_dir, out_dir)
        |> Map.put_new(:strip_dead_code, Keyword.get(opts, :strip_dead_code, true))

      _ ->
        %{out_dir: out_dir, strip_dead_code: Keyword.get(opts, :strip_dead_code, true)}
    end
  end

  defp direct_render_only_view_error?(%ArgumentError{} = exception, opts) do
    Map.get(opts, :direct_render_only) == true and
      String.contains?(
        Exception.message(exception),
        "direct_render_only requires"
      )
  end

  @doc """
  Returns `:ok` when a compile result has no error-severity diagnostics.
  """
  @spec validate_compile_result(%{project: map(), ir: map()}) :: :ok | {:error, [map()]}
  def validate_compile_result(%{project: _, ir: _} = result) do
    warnings = result |> compile_warnings() |> dedupe_warnings()

    if error_diagnostics?(warnings) do
      {:error, warnings}
    else
      :ok
    end
  end

  @doc false
  @spec project_run_from_compile({:ok, map()} | {:error, term()}, String.t()) :: project_run()
  def project_run_from_compile({:ok, result}, out_dir), do: compile_project_result(result, out_dir)

  def project_run_from_compile({:error, {:compile_diagnostics, warnings}}, out_dir) do
    %{
      status: :error,
      output: compile_output(:error, out_dir, dedupe_warnings(warnings)),
      warnings: dedupe_warnings(warnings)
    }
  end

  def project_run_from_compile({:error, error}, _out_dir) do
    %{
      status: :error,
      output: "compile: failed\n" <> DiagnosticFormatter.format_error(error),
      warnings: []
    }
  end

  @spec compile_project_result(%{project: map(), ir: map()}, String.t()) :: project_run()
  defp compile_project_result(result, out_dir) do
    warnings = result |> compile_warnings() |> dedupe_warnings()
    status = if error_diagnostics?(warnings), do: :error, else: :ok

    %{
      status: status,
      output: compile_output(status, out_dir, warnings),
      warnings: warnings
    }
  end

  @spec compile_output(run_status(), String.t(), [map()]) :: String.t()
  defp compile_output(:ok, out_dir, warnings) do
    [
      "compile: ok",
      "output: #{out_dir}",
      warnings_output(warnings)
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp compile_output(:error, out_dir, warnings) do
    [
      "compile: failed",
      "output: #{out_dir}",
      warnings_output(warnings)
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  @spec run_manifest(String.t()) :: :ok
  defp run_manifest(project_dir) do
    case manifest_project(project_dir) do
      %{status: :ok, output: output} ->
        IO.write(output)
        :ok

      %{status: :error, output: output} ->
        IO.puts(:stderr, output)
        System.halt(1)
    end
  end

  @doc """
  Runs `elmc manifest` in-process and returns CLI-compatible output for IDE integration.
  """
  @spec manifest_project(String.t()) :: manifest_run()
  def manifest_project(project_dir) do
    case Elmc.check(project_dir) do
      {:ok, project} ->
        manifest = build_manifest(project_dir, project)
        output = Jason.encode!(manifest, pretty: true)

        %{
          status: :ok,
          output: output,
          warnings: [],
          manifest: manifest
        }

      {:error, error} ->
        %{
          status: :error,
          output: "manifest: failed\n" <> DiagnosticFormatter.format_error(error),
          warnings: [],
          manifest: nil
        }
    end
  end

  @spec build_manifest(String.t(), map()) :: map()
  defp build_manifest(project_dir, project) do
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

    %{
      "supported_packages" => supported_packages,
      "excluded_packages" => excluded_packages,
      "modules_detected" => Enum.map(project.modules, & &1.name),
      "dependency_compatibility" => compatibility
    }
  end

  @spec warnings_output([map()]) :: String.t()
  defp warnings_output(warnings) when is_list(warnings) do
    rendered = DiagnosticFormatter.format_warnings(warnings)

    json_line =
      if warnings == [] do
        ""
      else
        "ELMC_WARNINGS_JSON:" <> Jason.encode!(warnings)
      end

    [rendered, json_line]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
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
          "code" => Map.get(warning, :code),
          "module" => Map.get(warning, :module),
          "function" => Map.get(warning, :function),
          "file" => Map.get(warning, :file),
          "line" => Map.get(warning, :line),
          "column" => Map.get(warning, :column),
          "constructor" => Map.get(warning, :constructor),
          "expected_kind" => Map.get(warning, :expected_kind),
          "has_arg_pattern" => Map.get(warning, :has_arg_pattern),
          "message" => Map.get(warning, :message, inspect(warning)),
          "severity" => Map.get(warning, :severity, "warning")
        }
      end)

    dedupe_warnings(project_warnings ++ ir_warnings)
  end

  @spec error_diagnostics?([map()]) :: boolean()
  defp error_diagnostics?(diagnostics) when is_list(diagnostics) do
    Enum.any?(diagnostics, &(diagnostic_severity(&1) == "error"))
  end

  @spec diagnostic_severity(cli_diagnostic()) :: String.t()
  defp diagnostic_severity(diagnostic) when is_map(diagnostic) do
    diagnostic
    |> Map.get("severity", Map.get(diagnostic, :severity, "warning"))
    |> to_string()
    |> String.downcase()
  end

  defp diagnostic_severity(_diagnostic), do: "warning"

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

  @spec warning_dedupe_key(cli_diagnostic() | map() | String.t() | atom()) :: warning_dedupe_key()
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

  @spec dependency_keys(map()) :: [String.t()]
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
