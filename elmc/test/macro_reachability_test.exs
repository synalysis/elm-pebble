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
end
