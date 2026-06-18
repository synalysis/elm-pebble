defmodule Elmc.GeneratedRcTrackListTest do
  @moduledoc """
  Reference-count probes for elm/core `List` codegen.

  Matrix coverage and probe lists live in `Elmc.Test.RcTrackMatrix`.
  """

  use ExUnit.Case, async: true

  alias Elmc.Test.RcTrackCoreTest
  alias Elmc.Test.RcTrackMatrix

  @module_name "List"

  @tag :rc_track
  @tag :rc_track_core
  @tag :rc_track_list
  test "elm/core List probes balance rc registry" do
    RcTrackCoreTest.run_core_module_suite!(@module_name, test_dir: __DIR__)
  end

  @tag :rc_track
  @tag :rc_track_core
  @tag :rc_track_list
  test "every codegen matrix List function has an rc probe" do
    %{probes: probes} = RcTrackMatrix.registry_entry(@module_name)

    RcTrackCoreTest.assert_matrix_coverage!(
      probes,
      RcTrackMatrix.functions_for(@module_name),
      @module_name,
      RcTrackMatrix.matrix_probe_exceptions(@module_name)
    )
  end
end
