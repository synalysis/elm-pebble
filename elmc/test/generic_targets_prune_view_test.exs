defmodule Elmc.GenericTargetsPruneViewTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.DirectRender.GenericTargets
  alias ElmEx.Frontend.Bridge
  alias ElmEx.IR.{DeadCode, Lowerer}

  @repo_root Path.expand("../..", __DIR__)
  @watch_info_src Path.join(@repo_root, "ide/priv/project_templates/watch_demo_watch_info/src")
  @bundled_sources [
    Path.join(@repo_root, "ide/priv/bundled_elm/pebble-watch-src"),
    Path.join(@repo_root, "ide/priv/bundled_elm/shared-elm/shared/elm")
  ]

  setup do
    tmp = Path.join(System.tmp_dir!(), "generic-targets-prune-view-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(tmp, "src"))
    File.cp_r!(@watch_info_src, Path.join(tmp, "src"))

    elm_json = %{
      "type" => "application",
      "source-directories" => ["src" | @bundled_sources],
      "elm-version" => "0.19.1",
      "dependencies" => %{
        "direct" => %{
          "elm/core" => "1.0.5",
          "elm/json" => "1.1.3"
        },
        "indirect" => %{}
      },
      "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
    }

    File.write!(Path.join(tmp, "elm.json"), Jason.encode!(elm_json, pretty: true))

    on_exit(fn -> File.rm_rf(tmp) end)

    {:ok, tmp: tmp}
  end

  test "prune_direct_generic drops generic view but keeps view helpers with wrapper ABI", %{tmp: tmp} do
    {:ok, project} = Bridge.load_project(tmp)
    {:ok, ir0} = Lowerer.lower_project(project)
    ir = DeadCode.strip(ir0, "Main")

    opts = %{
      entry_module: "Main",
      strip_dead_code: true,
      prune_direct_generic: true,
      prune_native_wrappers: true
    }

    function_targets = GenericTargets.function_targets(ir, opts)
    wrapper_targets = GenericTargets.wrapper_targets(ir, opts)

    assert MapSet.member?(function_targets, {"Main", "maybeLabel"})
    assert MapSet.member?(function_targets, {"Main", "watchModelLabel"})
    refute MapSet.member?(function_targets, {"Main", "view"})

    assert MapSet.member?(wrapper_targets, {"Main", "watchModelLabel"})
    assert MapSet.member?(wrapper_targets, {"Main", "maybeLabel"})
  end

  test "direct_render_only drops unused Pebble.Ui streaming glue helpers", %{tmp: tmp} do
    {:ok, project} = Bridge.load_project(tmp)
    {:ok, ir0} = Lowerer.lower_project(project)
    ir = DeadCode.strip(ir0, "Main")

    opts = %{
      entry_module: "Main",
      strip_dead_code: true,
      direct_render_only: true,
      prune_direct_generic: true
    }

    function_targets = GenericTargets.function_targets(ir, opts)

    refute MapSet.member?(function_targets, {"Pebble.Ui", "toUiNode"})
    refute MapSet.member?(function_targets, {"Pebble.Ui", "windowStack"})
    refute MapSet.member?(function_targets, {"Pebble.Ui", "window"})
    refute MapSet.member?(function_targets, {"Pebble.Ui", "canvasLayer"})
  end
end
