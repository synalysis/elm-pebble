defmodule Elmc.RuntimePruneClosureTest do
  use Elmc.TestSupport.PrimaryCodegenCase, async: false

  @source_fixture Path.expand("fixtures/simple_project", __DIR__)
  @project_dir Path.expand("tmp/runtime_prune_closure_project", __DIR__)
  @out_dir Path.expand("tmp/runtime_prune_closure_out", __DIR__)

  @closure_main """
  module Main exposing (main)

  import Json.Decode as Decode
  import Pebble.Platform as Platform
  import Pebble.Ui as Ui
  import Pebble.Ui.Color as Color

  bump : Int -> Int
  bump n =
      n + 1

  values : List Int
  values =
      List.map bump [ 0, 1, 2, 3 ]

  init _ =
      ( { count = List.length values }
      , Platform.Cmd.none
      )

  update _ model =
      ( model, Platform.Cmd.none )

  view model =
      Ui.clear Color.white
          |> Ui.toUiNode

  subscriptions _ =
      Platform.Sub.none

  main =
      Platform.application
          { init = init
          , update = update
          , view = view
          , subscriptions = subscriptions
          }
  """

  setup do
    File.rm_rf!(@project_dir)
    File.rm_rf!(@out_dir)
    File.cp_r!(@source_fixture, @project_dir)
    File.write!(Path.join(@project_dir, "src/Main.elm"), @closure_main)
    :ok
  end

  test "pruned runtime keeps multi-line static closure helpers referenced from elmc_closure_new" do
    assert {:ok, _} =
             Elmc.compile(@project_dir, %{
               out_dir: @out_dir,
               entry_module: "Main",
               direct_render_only: true,
               prune_runtime: true
             })

    runtime_path = Path.join(@out_dir, "runtime/elmc_runtime.c")
    runtime = File.read!(runtime_path)
    generated = File.read!(Path.join(@out_dir, "c/elmc_generated.c"))

    assert String.contains?(generated, "elmc_closure_new_rc"),
           "fixture must reference elmc_closure_new_rc so pruning keeps closure helpers"

    assert String.contains?(runtime, "elmc_closure_cell_init("),
           "expected elmc_closure_cell_init definition in pruned runtime"

    refute Regex.match?(~r/static RC elmc_closure_cell_init\([^)]*\)\s*;/, runtime),
           "expected full elmc_closure_cell_init body, not a forward declaration only"

    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for runtime prune closure test")

    harness_path = Path.join(@out_dir, "runtime_prune_closure_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_pebble.h"

      int main(void) {
        ElmcValue *captures[1] = {elmc_int_zero()};
        ElmcValue *closure = NULL;
        if (elmc_closure_new_rc(&closure, NULL, 0, 1, captures) != RC_SUCCESS) return 1;
        elmc_release(closure);
        return 0;
      }
      """
    )

    {compile_out, compile_code} =
      System.cmd(cc, [
        "-std=c11",
        "-Wall",
        "-Wextra",
        "-Werror=implicit-function-declaration",
        "-include", Path.expand("support/elmc_host_stubs.h", __DIR__),
        "-I#{Path.join(@out_dir, "runtime")}",
        "-I#{Path.join(@out_dir, "ports")}",
        "-I#{Path.join(@out_dir, "c")}",
        runtime_path,
        Path.join(@out_dir, "ports/elmc_ports.c"),
        Path.join(@out_dir, "c/elmc_generated.c"),
        Path.join(@out_dir, "c/elmc_worker.c"),
        Path.join(@out_dir, "c/elmc_pebble.c"),
        harness_path,
        "-lm",
        "-o",
        Path.join(@out_dir, "runtime_prune_closure_harness")
      ])

    assert compile_code == 0, compile_out
  end
end
