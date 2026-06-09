defmodule Elmc.Test.RcTrackHarness do
  @moduledoc false

  import ExUnit.Assertions, only: [flunk: 1]

  @type compile_opts :: keyword()

  @spec compile!(String.t(), String.t(), compile_opts()) :: :ok
  def compile!(project_dir, out_dir, opts \\ []) do
    compile_opts =
      Keyword.merge(
        [out_dir: out_dir, strip_dead_code: false],
        opts
      )

    case Elmc.compile(project_dir, compile_opts) do
      {:ok, _} -> :ok
      {:error, reason} -> flunk("compile failed: #{inspect(reason)}")
    end
  end

  @spec cc_flags(String.t()) :: [String.t()]
  def cc_flags(out_dir) do
    [
      "-std=c11",
      "-Wall",
      "-Wextra",
      "-DELMC_RC_TRACK=1",
      "-I#{Path.join(out_dir, "runtime")}",
      "-I#{Path.join(out_dir, "ports")}",
      "-I#{Path.join(out_dir, "c")}"
    ]
  end

  @spec run_harness!(String.t(), String.t(), String.t(), keyword()) :: String.t()
  def run_harness!(out_dir, harness_path, binary_name, opts \\ []) do
    cc = System.find_executable("cc") || flunk("cc not available for rc track harness")

    sources =
      Keyword.get_lazy(opts, :sources, fn ->
        [
          Path.join(out_dir, "runtime/elmc_runtime.c"),
          Path.join(out_dir, "ports/elmc_ports.c"),
          harness_path
        ]
      end)

    binary_path = Path.join(out_dir, binary_name)

    {compile_out, compile_code} =
      System.cmd(cc, cc_flags(out_dir) ++ sources ++ ["-o", binary_path])

    if compile_code != 0, do: flunk("harness compile failed:\n#{compile_out}")

    {run_out, run_code} = System.cmd(binary_path, [], stderr_to_stdout: true)

    if run_code != 0 do
      flunk("rc track harness failed (exit #{run_code}):\n#{run_out}")
    end

    run_out
  end

  @spec assert_balanced!(String.t()) :: :ok
  def assert_balanced!(run_out) do
    if String.contains?(run_out, "rc_ok") do
      :ok
    else
      flunk("expected balanced rc registry, got:\n#{run_out}")
    end
  end

  @spec worker_sources(String.t()) :: [String.t()]
  def worker_sources(out_dir) do
    [
      Path.join(out_dir, "runtime/elmc_runtime.c"),
      Path.join(out_dir, "ports/elmc_ports.c"),
      Path.join(out_dir, "c/elmc_generated.c"),
      Path.join(out_dir, "c/elmc_pebble.c"),
      Path.join(out_dir, "c/elmc_worker.c")
    ]
  end

  @spec run_worker_harness!(String.t(), String.t(), String.t()) :: String.t()
  def run_worker_harness!(out_dir, harness_path, binary_name) do
    run_harness!(
      out_dir,
      harness_path,
      binary_name,
      sources: worker_sources(out_dir) ++ [harness_path]
    )
  end

  @type probe_spec :: %{
          name: String.t(),
          c_symbol: String.t(),
          release_result: boolean()
        }

  @doc """
  Build and run a host harness that checks ELMC_RC_TRACK balance for each probe.

  `module` is the Elm entry module (for example `"RcTrackListProbe"`).
  Each probe is a nullary generated function `elmc_fn_<Module>_<probe>`.
  """
  @spec run_probe_suite!(String.t(), String.t(), String.t(), [probe_spec()]) :: String.t()
  def run_probe_suite!(out_dir, module_name, binary_name, probes) do
    harness_path = Path.join(out_dir, "c/#{binary_name}_harness.c")
    probe_cases = Enum.map_join(probes, "\n", &probe_case_c/1)

    File.write!(
      harness_path,
      """
      #include "elmc_generated.h"
      #include "elmc_generated.c"
      #include <stdio.h>

      static int run_probe(const char *name, ElmcValue *(*fn)(void), int release_result) {
        elmc_rc_track_reset();
        ElmcValue *out = fn();
        if (release_result && out) elmc_release(out);
        if (!elmc_rc_track_check_balanced()) {
          fprintf(stderr, "rc leak in %s\\n", name);
          return 1;
        }
        return 0;
      }

      #{probe_thunks(module_name, probes)}

      int main(void) {
      #{probe_cases}
        printf("rc_ok #{module_name} probes=%d\\n", #{length(probes)});
        return 0;
      }
      """
    )

    run_harness!(out_dir, harness_path, binary_name)
  end

  @spec int_probes([String.t()]) :: [probe_spec()]
  def int_probes(names) do
    Enum.map(names, fn name ->
      %{name: name, c_symbol: name, release_result: true}
    end)
  end

  @spec list_probes([String.t()]) :: [probe_spec()]
  def list_probes(names) do
    Enum.map(names, fn name ->
      %{name: name, c_symbol: name, release_result: true}
    end)
  end

  defp probe_thunks(module_name, probes) do
    Enum.map_join(probes, "\n", fn %{c_symbol: symbol} ->
      """
      static ElmcValue *#{symbol}_probe(void) {
        return elmc_fn_#{module_name}_#{symbol}(NULL, 0);
      }
      """
    end)
  end

  defp probe_case_c(%{name: name, c_symbol: symbol, release_result: release_result}) do
    release = if release_result, do: "1", else: "0"

    """
        if (run_probe("#{name}", #{symbol}_probe, #{release}) != 0) return 1;
    """
  end
end
