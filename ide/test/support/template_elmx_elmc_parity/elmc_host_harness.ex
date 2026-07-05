defmodule Ide.Test.TemplateElmxElmcParity.ElmcHostHarness do
  @moduledoc false

  @runtime_link_stub Path.expand("../../../elmc/test/support/elmc_runtime_link_stubs.c", __DIR__)
  @harness_name "template_parity_harness"
  @default_run_timeout_sec 120

  @spec compile!(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def compile!(project_dir, out_dir, opts \\ []) do
    compile_opts = Keyword.merge([out_dir: out_dir, strip_dead_code: false], opts)

    case Elmc.compile(project_dir, compile_opts) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:elmc_compile_failed, reason}}
    end
  end

  @spec run_capture(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def run_capture(out_dir, harness_path, binary_name, opts \\ []) do
    cc = System.find_executable("cc")

    if is_nil(cc) do
      {:error, :cc_not_available}
    else
      sources = Keyword.get_lazy(opts, :sources, fn -> default_sources(out_dir, harness_path) end)
      binary_path = Path.join(out_dir, binary_name)
      stop_running_harnesses!(out_dir)

      {compile_out, compile_code} =
        System.cmd(cc, compile_and_link_args(out_dir, sources, binary_path, opts), stderr_to_stdout: true)

      cond do
        compile_code != 0 ->
          {:error, {:harness_compile_failed, compile_out}}

        true ->
          timeout_sec = Keyword.get(opts, :timeout_sec, default_run_timeout_sec())

          case run_binary_with_timeout(binary_path, timeout_sec) do
            {:ok, run_out} ->
              {:ok, run_out}

            {:error, _} = err ->
              stop_running_harnesses!(out_dir)
              err
          end
      end
    end
  end

  @doc false
  @spec stop_running_harnesses!(String.t()) :: :ok
  def stop_running_harnesses!(out_dir) when is_binary(out_dir) do
    binary_path = Path.join(out_dir, @harness_name)
    kill_matching_processes(escape_pgrep_pattern(binary_path))
    :ok
  end

  @doc false
  @spec cleanup_stale_harnesses!() :: :ok
  def cleanup_stale_harnesses! do
    kill_matching_processes(~s(/tmp/ide-template-parity-[^/]+/#{@harness_name}))
    :ok
  end

  defp run_binary_with_timeout(binary_path, timeout_sec) do
    timeout_bin = System.find_executable("timeout")
    bash = System.find_executable("bash")

    {run_out, run_code} =
      cond do
        is_binary(timeout_bin) and is_binary(bash) ->
          System.cmd(
            bash,
            [
              "-c",
              "ulimit -v unlimited 2>/dev/null || true; exec #{inspect(timeout_bin)} #{Integer.to_string(timeout_sec)} #{inspect(binary_path)}"
            ],
            stderr_to_stdout: true
          )

        is_binary(timeout_bin) ->
          System.cmd(timeout_bin, [Integer.to_string(timeout_sec), binary_path], stderr_to_stdout: true)

        is_binary(bash) ->
          System.cmd(bash, ["-c", "ulimit -v unlimited 2>/dev/null || true; exec #{inspect(binary_path)}"],
            stderr_to_stdout: true
          )

        true ->
          System.cmd(binary_path, [], stderr_to_stdout: true)
      end

    cond do
      run_code == 0 ->
        {:ok, run_out}

      run_code == 124 ->
        {:error, {:harness_timeout, timeout_sec, run_out}}

      true ->
        {:error, {:harness_run_failed, run_code, run_out}}
    end
  end

  defp kill_matching_processes(pattern) when is_binary(pattern) do
    case System.cmd("pgrep", ["-f", pattern], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.each(&terminate_pid/1)

      _ ->
        :ok
    end
  end

  defp terminate_pid(pid_string) when is_binary(pid_string) do
    with {pid, _} <- Integer.parse(String.trim(pid_string)) do
      _ = System.cmd("kill", ["-TERM", Integer.to_string(pid)], stderr_to_stdout: true)
      Process.sleep(50)
      _ = System.cmd("kill", ["-KILL", Integer.to_string(pid)], stderr_to_stdout: true)
    end

    :ok
  end

  defp escape_pgrep_pattern(path) do
    String.replace(path, ".", "\\.")
  end

  defp default_run_timeout_sec do
    case System.get_env("PARITY_HARNESS_TIMEOUT_SEC") do
      nil -> @default_run_timeout_sec
      value -> String.to_integer(value)
    end
  end

  defp default_sources(out_dir, harness_path) do
    [
      Path.join(out_dir, "runtime/elmc_runtime.c"),
      Path.join(out_dir, "ports/elmc_ports.c"),
      harness_path
    ]
  end

  defp compile_and_link_args(out_dir, sources, binary_path, opts) do
    cc_flags(out_dir, opts) ++ with_runtime_link_stub(sources) ++ ["-lm", "-o", binary_path]
  end

  defp cc_flags(out_dir, opts) do
    [
      "-std=c11",
      "-Wall",
      "-Wextra",
      "-I#{Path.join(out_dir, "runtime")}",
      "-I#{Path.join(out_dir, "ports")}",
      "-I#{Path.join(out_dir, "c")}"
    ] ++ Keyword.get(opts, :extra_flags, [])
  end

  defp with_runtime_link_stub(sources) do
    if Enum.any?(sources, &links_generated_c?/1), do: sources, else: sources ++ [@runtime_link_stub]
  end

  defp links_generated_c?(path) do
    cond do
      String.contains?(path, "elmc_generated.c") ->
        true

      String.ends_with?(path, "_harness.c") ->
        case File.read(path) do
          {:ok, source} -> String.contains?(source, ~s/#include "elmc_generated.c"/)
          _ -> false
        end

      true ->
        false
    end
  end
end
