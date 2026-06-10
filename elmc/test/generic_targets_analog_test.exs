defmodule Elmc.GenericTargetsAnalogTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.DirectRender.GenericTargets
  alias Elmc.Backend.CCodegen.IRQueries
  alias ElmEx.Frontend.Bridge
  alias ElmEx.IR.{DeadCode, Lowerer}

  @repo_root Path.expand("../..", __DIR__)
  @analog_src Path.join(@repo_root, "ide/priv/project_templates/watchface_analog/src")
  @bundled_sources [
    Path.join(@repo_root, "ide/priv/bundled_elm/pebble-watch-src"),
    Path.join(@repo_root, "ide/priv/bundled_elm/shared-elm/shared/elm"),
    Path.join(@repo_root, "ide/priv/internal_packages/elm-time/src"),
    Path.join(@repo_root, "ide/priv/internal_packages/elm-random/src")
  ]

  setup do
    tmp = Path.join(System.tmp_dir!(), "generic-targets-analog-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(tmp, "src"))
    File.cp_r!(@analog_src, Path.join(tmp, "src"))

    sources =
      ["src" | @bundled_sources]

    elm_json = %{
      "type" => "application",
      "source-directories" => sources,
      "elm-version" => "0.19.1",
      "dependencies" => %{
        "direct" => %{
          "elm/core" => "1.0.5",
          "elm/json" => "1.1.3",
          "elm/time" => "1.0.0"
        },
        "indirect" => %{}
      },
      "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
    }

    File.write!(Path.join(tmp, "elm.json"), Jason.encode!(elm_json, pretty: true))

    on_exit(fn -> File.rm_rf(tmp) end)

    {:ok, tmp: tmp}
  end

  test "watchface analog generic target analysis stays linear in nested view lets", %{tmp: tmp} do
    {:ok, project} = Bridge.load_project(tmp)
    {:ok, ir0} = Lowerer.lower_project(project)
    ir = DeadCode.strip(ir0, "Main")
    opts = %{entry_module: "Main", strip_dead_code: true}

    {micros, targets} =
      :timer.tc(fn -> GenericTargets.function_targets(ir, opts) end)

    assert micros < 5_000_000, "generic target analysis took #{micros / 1000}ms"
    assert MapSet.member?(targets, {"Main", "handX"})
    assert MapSet.member?(targets, {"Main", "handY"})
    assert MapSet.member?(targets, {"Main", "unit12X"})
    refute MapSet.member?(targets, {"Main", "view"})

    decl_map = IRQueries.function_decl_map(ir)
    view = Map.fetch!(decl_map, {"Main", "view"})
    assert is_map(view.expr)
  end
end
