defmodule Elmc.MacroReachabilityTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.CCodegen.{IRQueries, MacroReachability, UnionMacros}
  alias Elmc.Backend.CCodegen.DirectRender.GenericTargets
  alias Elmc.Backend.CCodegen.Host

  @game_2048_main Path.expand("../../ide/priv/project_templates/game_2048/src/Main.elm", __DIR__)

  test "reachable union macros omit unused platform companion tags" do
    project_dir = Path.expand("tmp/macro_reachability_2048", __DIR__)
    File.rm_rf!(project_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), File.read!(@game_2048_main))
    File.write!(Path.join(project_dir, "elm.json"), File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__)))

    assert {:ok, %{ir: ir}} =
             Elmc.compile(project_dir, %{
               entry_module: "Main",
               out_dir: Path.join(project_dir, "out")
             })

    decl_map = IRQueries.function_decl_map(ir)
    opts = [entry_module: "Main", direct_render_only: true, strip_dead_code: true]

    targets =
      GenericTargets.function_targets(ir, opts)
      |> MapSet.union(Host.direct_command_targets(ir, opts, decl_map))

    used = MacroReachability.used_union_ctors(decl_map, targets)
    {defines, _macros} = UnionMacros.definitions(ir, used_union_ctors: used)

    assert defines =~ "ELMC_UNION_LEFT"
    refute defines =~ "ELMC_UNION_COMPANION_TYPES_BERLIN"
    assert String.split(defines, "\n") |> length() < 40
  end

  test "nested union constructor patterns in case branches are reachable" do
    project_dir = Path.expand("tmp/macro_reachability_nested", __DIR__)
    File.rm_rf!(project_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    template = Path.expand("../../ide/priv/project_templates/watchface_yes", __DIR__)
    File.cp_r!(template, project_dir)

    File.write!(
      Path.join(project_dir, "elm.json"),
      Jason.encode!(%{
        "type" => "application",
        "source-directories" => [
          "src",
          "protocol/src",
          "../../../../packages/elm-pebble/elm-watch/src"
        ],
        "elm-version" => "0.19.1",
        "dependencies" => %{
          "direct" => %{"elm/core" => "1.0.5", "elm/json" => "1.1.3", "elm/time" => "1.0.0"},
          "indirect" => %{}
        },
        "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
      })
    )

    assert {:ok, %{ir: ir}} =
             Elmc.compile(project_dir, %{
               entry_module: "Main",
               out_dir: Path.join(project_dir, "out")
             })

    decl_map = IRQueries.function_decl_map(ir)

    opts = [
      entry_module: "Main",
      direct_render_only: true,
      strip_dead_code: true,
      prune_runtime: true,
      pebble_int32: true
    ]

    generic_targets = GenericTargets.function_targets(ir, opts)

    {_def_targets, direct_emit_targets, _pruned} =
      Elmc.Backend.CCodegen.DirectRender.Analysis.target_sets(decl_map, opts)

    used =
      MacroReachability.used_union_ctors(
        decl_map,
        MapSet.union(generic_targets, direct_emit_targets)
      )

    assert MapSet.member?(used, "PolarDay")
    assert MapSet.member?(used, "PolarNight")
    assert MapSet.member?(used, "Celsius")
    assert MapSet.member?(used, "Companion.Types.PolarDay")

    {defines, _macros} = UnionMacros.definitions(ir, used_union_ctors: used)

    assert defines =~ "ELMC_UNION_COMPANION_TYPES_POLARDAY"
    assert defines =~ "ELMC_UNION_COMPANION_TYPES_POLARNIGHT"
    assert defines =~ "ELMC_UNION_COMPANION_TYPES_CELSIUS"
  end
end
