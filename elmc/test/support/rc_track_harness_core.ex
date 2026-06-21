defmodule Elmc.Test.RcTrackCoreTest do
  @moduledoc false

  import ExUnit.Assertions

  alias Elmc.Test.RcTrackHarness
  alias Elmc.Test.RcTrackMatrix

  @spec run_int_suite!(keyword()) :: String.t()
  def run_int_suite!(opts) do
    project_dir = Keyword.fetch!(opts, :project_dir)
    out_dir = Keyword.fetch!(opts, :out_dir)
    module = Keyword.fetch!(opts, :module)
    binary = Keyword.fetch!(opts, :binary)
    probes = Keyword.fetch!(opts, :probes)

    File.rm_rf!(out_dir)
    RcTrackHarness.compile!(project_dir, out_dir, entry_module: module)

    out =
      RcTrackHarness.run_probe_suite!(
        out_dir,
        module,
        binary,
        RcTrackHarness.int_probes(probes)
      )

    RcTrackHarness.assert_balanced!(out)
    assert out =~ "probes=#{length(probes)}"
    out
  end

  @spec run_core_module_suite!(String.t(), keyword()) :: String.t()
  def run_core_module_suite!(module_name, opts) do
    entry = RcTrackMatrix.registry_entry(module_name)
    project_dir = Keyword.get(opts, :project_dir, Path.expand(entry.fixture, Keyword.fetch!(opts, :test_dir)))
    out_dir = Keyword.get(opts, :out_dir, Path.expand("tmp/rc_track_#{String.downcase(module_name)}", Keyword.fetch!(opts, :test_dir)))
    binary = Keyword.get(opts, :binary, "rc_track_#{String.downcase(module_name)}")

    int_probes = RcTrackMatrix.int_probes_for(module_name)
    heap_probes = RcTrackMatrix.heap_result_probes(module_name)

    File.rm_rf!(out_dir)

    compile_opts =
      if module_name == "Debug" do
        [entry_module: entry.module, prod: false]
      else
        [entry_module: entry.module]
      end

    RcTrackHarness.compile!(project_dir, out_dir, compile_opts)

    int_out =
      if int_probes == [] do
        ""
      else
        RcTrackHarness.run_probe_suite!(
          out_dir,
          entry.module,
          binary,
          RcTrackHarness.int_probes(int_probes)
        )
      end

    heap_out =
      if heap_probes == [] do
        ""
      else
        RcTrackHarness.run_probe_suite!(
          out_dir,
          entry.module,
          "#{binary}_heap",
          RcTrackHarness.list_probes(heap_probes)
        )
      end

    RcTrackHarness.assert_balanced!(int_out <> heap_out)

    if int_probes != [] do
      assert int_out =~ "probes=#{length(int_probes)}"
    end

    if heap_probes != [] do
      assert heap_out =~ "probes=#{length(heap_probes)}"
    end

    int_out <> heap_out
  end

  @spec assert_matrix_coverage!([String.t()], [String.t()], String.t(), map()) :: :ok
  def assert_matrix_coverage!(probes, matrix_functions, prefix, exceptions \\ %{}) do
    covered =
      Enum.map(probes, fn probe ->
        probe
        |> String.replace_prefix("probe", "")
        |> then(&Map.get(exceptions, &1, "#{prefix}." <> lowercase_first(&1)))
      end)

    missing = matrix_functions -- covered
    assert missing == [], "missing #{prefix} rc probes for: #{inspect(missing)}"
  end

  defp lowercase_first <<first::utf8, rest::binary>> do
    String.downcase(<<first::utf8>>) <> rest
  end
end
