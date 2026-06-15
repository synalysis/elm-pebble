defmodule Elmc.Test.RcTrackCoreTest do
  @moduledoc false

  import ExUnit.Assertions

  alias Elmc.Test.RcTrackHarness

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
