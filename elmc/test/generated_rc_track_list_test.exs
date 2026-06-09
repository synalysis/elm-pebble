defmodule Elmc.GeneratedRcTrackListTest do
  @moduledoc """
  Reference-count probes for elm/core `List` codegen.

  Each probe is an independent nullary Elm function that exercises one `List.*`
  API and returns a checksum `Int` (or `List Int` for explicit list results).
  The host harness resets `ELMC_RC_TRACK` per probe and requires alloc/release
  balance after inputs and outputs are released.

  Extend `@list_int_probes` / `@list_list_probes` as new List functions land in
  the compiler; mirror names in `RcTrackListProbe.elm`.
  """

  use ExUnit.Case, async: true

  alias Elmc.Test.RcTrackHarness

  @module "RcTrackListProbe"
  @project_dir Path.expand("fixtures/rc_track_list_project", __DIR__)
  @out_dir Path.expand("tmp/rc_track_list", __DIR__)

  # Mirrors elmc/docs/CODEGEN_COVERAGE_MATRIX.md — elm/core: List
  @list_int_probes ~w(
    probeIsEmpty probeLength probeHead probeTail probeReverse probeMember
    probeMap probeFilter probeFoldl probeFoldr probeAppend probeConcat
    probeConcatMap probeIndexedMap probeFilterMap probeSum probeProduct
    probeMaximum probeMinimum probeAny probeAll probeSort probeSortBy
    probeSortWith probeSingleton probeRange probeRepeat probeTake probeDrop
    probePartition probeUnzip probeIntersperse probeMap2 probeMap3 probeCons
  )

  @list_list_probes ["probeReverseList"]

  setup do
    File.rm_rf!(@out_dir)
    RcTrackHarness.compile!(@project_dir, @out_dir, entry_module: @module)
    :ok
  end

  @tag :rc_track
  @tag :rc_track_core
  @tag :rc_track_list
  test "elm/core List int probes balance rc registry" do
    probes = RcTrackHarness.int_probes(@list_int_probes)

    out =
      RcTrackHarness.run_probe_suite!(
        @out_dir,
        @module,
        "rc_track_list_int",
        probes
      )

    RcTrackHarness.assert_balanced!(out)
    assert out =~ "probes=#{length(@list_int_probes)}"
  end

  @tag :rc_track
  @tag :rc_track_core
  @tag :rc_track_list
  test "elm/core List list-result probes balance rc registry" do
    probes = RcTrackHarness.list_probes(@list_list_probes)

    out =
      RcTrackHarness.run_probe_suite!(
        @out_dir,
        @module,
        "rc_track_list_list",
        probes
      )

    RcTrackHarness.assert_balanced!(out)
    assert out =~ "probes=#{length(@list_list_probes)}"
  end

  @tag :rc_track
  @tag :rc_track_core
  @tag :rc_track_list
  test "every codegen matrix List function has an rc probe" do
    matrix_functions = [
      "List.head",
      "List.tail",
      "List.isEmpty",
      "List.length",
      "List.reverse",
      "List.member",
      "List.map",
      "List.filter",
      "List.foldl",
      "List.foldr",
      "List.append",
      "List.concat",
      "List.concatMap",
      "List.indexedMap",
      "List.filterMap",
      "List.sum",
      "List.product",
      "List.maximum",
      "List.minimum",
      "List.any",
      "List.all",
      "List.sort",
      "List.sortBy",
      "List.sortWith",
      "List.singleton",
      "List.range",
      "List.repeat",
      "List.take",
      "List.drop",
      "List.partition",
      "List.unzip",
      "List.intersperse",
      "List.map2",
      "List.map3",
      "List.cons"
    ]

    covered =
      Enum.map(@list_int_probes ++ @list_list_probes, fn probe ->
        probe
        |> String.replace_prefix("probe", "")
        |> list_probe_to_matrix_name()
      end)

    missing = matrix_functions -- covered
    assert missing == [], "missing List rc probes for: #{inspect(missing)}"
  end

  defp list_probe_to_matrix_name("Cons"), do: "List.cons"
  defp list_probe_to_matrix_name("ReverseList"), do: "List.reverse"

  defp list_probe_to_matrix_name(suffix) do
    "List." <> lowercase_first(suffix)
  end

  defp lowercase_first <<first::utf8, rest::binary>> do
    String.downcase(<<first::utf8>>) <> rest
  end
end
