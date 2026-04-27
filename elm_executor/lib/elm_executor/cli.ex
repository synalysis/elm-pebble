defmodule ElmExecutor.CLI do
  @moduledoc """
  CLI entrypoint for elm_executor operations.
  """

  alias ElmEx.DiagnosticFormatter

  @spec main([String.t()]) :: :ok | no_return()
  def main(argv) do
    case argv do
      ["check", project_dir] ->
        run_check(project_dir)

      ["compile", project_dir, "--out-dir", out_dir] ->
        run_compile(project_dir, out_dir, :library)

      ["compile", project_dir, "--out-dir", out_dir, "--mode", "ide_runtime"] ->
        run_compile(project_dir, out_dir, :ide_runtime)

      _ ->
        print_help()
    end
  end

  @spec run_check(term()) :: term()
  defp run_check(project_dir) do
    case ElmExecutor.check(project_dir) do
      {:ok, project} ->
        IO.puts("check: ok")
        IO.puts("modules: #{length(project.modules)}")

      {:error, error} ->
        IO.puts(:stderr, "check: failed")
        IO.puts(:stderr, DiagnosticFormatter.format_error(error))
        System.halt(1)
    end
  end

  @spec run_compile(term(), term(), term()) :: term()
  defp run_compile(project_dir, out_dir, mode) do
    case ElmExecutor.compile(project_dir, %{out_dir: out_dir, mode: mode}) do
      {:ok, _result} ->
        IO.puts("compile: ok")
        IO.puts("output: #{out_dir}")
        IO.puts("mode: #{mode}")

      {:error, error} ->
        IO.puts(:stderr, "compile: failed")
        IO.puts(:stderr, DiagnosticFormatter.format_error(error))
        System.halt(1)
    end
  end

  @spec print_help() :: term()
  defp print_help do
    IO.puts("""
    elm_executor usage:
      elm_executor check <project_dir>
      elm_executor compile <project_dir> --out-dir <dir>
      elm_executor compile <project_dir> --out-dir <dir> --mode ide_runtime
    """)
  end
end
