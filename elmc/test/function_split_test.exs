defmodule Elmc.FunctionSplitTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.CCodegen.FunctionSplit
  alias Elmc.Backend.CCodegen.IRQueries

  @source_template Path.expand("../../ide/priv/project_templates/watchface_yes", __DIR__)

  defp prepare_yes_project!(project_dir) do
    File.rm_rf!(project_dir)
    File.cp_r!(@source_template, project_dir)

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
  end

  defp yes_draw_dial_decl!(project_dir) do
    {:ok, %{ir: ir}} =
      Elmc.compile(project_dir, %{
        out_dir: Path.join(project_dir, ".ir-only"),
        entry_module: "Main",
        direct_render_only: true,
        prune_runtime: true,
        pebble_int32: true,
        strip_dead_code: true
      })

    Map.fetch!(IRQueries.function_decl_map(ir), {"Main", "drawDial"})
  end

  test "drawDial split part0 nests sunWindow as outermost let" do
    project_dir = Path.expand("tmp/function_split_yes_plan_project", __DIR__)
    prepare_yes_project!(project_dir)
    decl = yes_draw_dial_decl!(project_dir)

    {:ok, parts} = FunctionSplit.plan_parts_for_test(decl.expr, decl.args || [])
    {part0_names, part0} = hd(parts)

    assert hd(part0_names) == "moonBounds"
    assert List.last(part0_names) == "sunWindow"
    assert match?(%{op: :let_in, name: "sunWindow"}, part0)
  end

  test "drawDial split parts compile without phantom zero-arg let calls" do
    project_dir = Path.expand("tmp/function_split_yes_project", __DIR__)
    out_dir = Path.expand("tmp/function_split_yes_codegen", __DIR__)
    prepare_yes_project!(project_dir)
    File.rm_rf!(out_dir)

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               direct_render_only: true,
               prune_runtime: true,
               pebble_int32: true,
               strip_dead_code: true
             })

    generated = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated =~ "elmc_fn_Main_drawDial_part0_native"
    refute generated =~ "elmc_fn_Main_sunsetAngle(NULL"
    refute generated =~ "elmc_fn_Main_sunriseAngle(NULL"
    refute generated =~ "elmc_fn_Main_sunset(NULL"
    refute generated =~ "elmc_fn_Main_sunrise(NULL"
    refute generated =~ "elmc_fn_Main_sunWindow(NULL"

    part0_body =
      generated
      |> String.split("static RC elmc_fn_Main_drawDial_part0_native")
      |> tl()
      |> hd()
      |> String.split("static RC elmc_fn_Main_drawDial_part1_native")
      |> hd()

    assert part0_body =~ "elmc_maybe_with_default"
    assert part0_body =~ "elmc_fn_Main_square_native"
  end
end
