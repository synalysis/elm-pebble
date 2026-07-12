defmodule Elmc.PlanParityTest do
  use ExUnit.Case, async: false

  @moduletag :plan_parity

  alias Elmc.Test.CCodegenExtract

  test "primary plan path emits RC shell for init with Cmd.none" do
    source = """
    module Main exposing (init)

    import Pebble.Cmd

    type alias Model = ()
    type Msg = NoOp

    init : () -> ( Model, Cmd Msg )
    init _ =
        ( (), Cmd.none )
    """

    primary_c =
      compile_c!(source, "plan_parity_init", %{
        plan_ir_mode: :primary,
        strip_dead_code: false
      })

    assert primary_c =~ "elmc_fn_Main_init"
    init_body = CCodegenExtract.fn_body(primary_c, "elmc_fn_Main_init")
    assert init_body =~ "CATCH_BEGIN"
    assert init_body =~ "CHECK_RC(Rc)"
    refute init_body =~ "CATCH_BEGIN\n    CATCH_BEGIN"
  end

  test "companion send plan lowers params to owned not out" do
    plan = Elmc.PlanFixtures.companion_send_plan()
    c = Elmc.Backend.C.Lower.Function.emit(plan)
    assert c =~ "owned["
    assert c =~ "elmc_cmd2"
    refute c =~ "watchToPhoneTag(out"
  end

  test "primary lowers update with tagged Msg switch" do
    primary_c = compile_fixture!(%{plan_ir_mode: :primary, strip_dead_code: true})

    assert primary_c =~ "elmc_fn_Main_update"
    assert primary_c =~ "goto elmc_plan_block_"
    assert primary_c =~ "elmc_fn_Main_moveBoard"
    assert primary_c =~ "CHECK_RC(Rc)"
  end

  test "primary lowers moveBoard via direct native ABI wrapper" do
    primary_c = compile_fixture!(%{plan_ir_mode: :primary, strip_dead_code: true})

    body = CCodegenExtract.fn_body(primary_c, "elmc_fn_Main_moveBoard")
    assert body =~ "elmc_fn_Main_moveBoard_native"
    assert body =~ "direct_call_abi"
  end

  test "primary lowers drawCell with render ops" do
    primary_c = compile_fixture!(%{plan_ir_mode: :primary, strip_dead_code: true})

    body = CCodegenExtract.fn_body(primary_c, "elmc_fn_Main_drawCell")
    assert body =~ "elmc_render_cmd" or body =~ "goto elmc_plan_block_"
    assert body =~ "CHECK_RC(Rc)"
  end

  test "primary lowers subscriptions via plan path" do
    primary_c = compile_fixture!(%{plan_ir_mode: :primary, strip_dead_code: true})

    subs_body = CCodegenExtract.fn_body(primary_c, "elmc_fn_Main_subscriptions")
    assert subs_body =~ "elmc_sub"
  end

  test "primary coverage lowers all simple_project Main helpers" do
    {:ok, result} =
      Elmc.compile(
        Path.expand("fixtures/simple_project", __DIR__),
        %{
          out_dir: Path.expand("tmp/plan_primary_coverage_codegen", __DIR__),
          entry_module: "Main",
          strip_dead_code: true
        }
      )

    Process.put(:elmc_constructor_tags, Elmc.Backend.CCodegen.IRQueries.constructor_tag_map(result.ir))

    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    decl_map =
      result.ir.modules
      |> Enum.flat_map(fn mod ->
        mod.declarations
        |> Enum.filter(&(&1.kind == :function))
        |> Enum.map(fn decl -> {{mod.name, decl.name}, decl} end)
      end)
      |> Map.new()

    report = Elmc.Backend.Plan.PrimaryCoverage.main_functions_report(decl_map)

    assert report.lowered == report.total,
           "expected all Main functions to lower, got #{inspect(report.failed)}"

    assert report.lowered >= 12
  end

  test "primary compiles simple_project update with plan blocks" do
    primary_c = compile_fixture!(%{plan_ir_mode: :primary, strip_dead_code: true})

    assert primary_c =~ "elmc_fn_Main_update"
    assert primary_c =~ "elmc_fn_Main_moveBoard"
    assert primary_c =~ "CHECK_RC(Rc)"

    primary_update = CCodegenExtract.fn_body(primary_c, "elmc_fn_Main_update")
    assert primary_update =~ "goto elmc_plan_block_"
    assert primary_update =~ "switch"
  end

  defp compile_fixture!(opts) do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/plan_parity_fixture_project", __DIR__)
    out_dir = Path.expand("tmp/plan_parity_fixture_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    assert {:ok, _} =
             Elmc.compile(
               project_dir,
               Map.merge(
                 %{
                   out_dir: out_dir,
                   entry_module: "Main",
                   strip_dead_code: true
                 },
                 Map.new(opts)
               )
             )

    File.read!(Path.join(out_dir, "c/elmc_generated.c"))
  end

  defp compile_c!(source, name, opts) when is_binary(source) and byte_size(source) > 200 do
    compile_c!(source, name, opts, :fixture_path)
  end

  defp compile_c!(source, name, opts) do
    compile_c!(source, name, opts, :inline)
  end

  defp compile_c!(source, name, opts, mode) do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/#{name}_project", __DIR__)
    out_dir = Path.expand("tmp/#{name}_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    main_src =
      case mode do
        :fixture_path -> File.read!(Path.expand(source, __DIR__))
        :inline -> source
      end

    File.write!(Path.join(project_dir, "src/Main.elm"), main_src)

    assert {:ok, _} =
             Elmc.compile(
               project_dir,
               Map.merge(
                 %{
                   out_dir: out_dir,
                   entry_module: "Main",
                   strip_dead_code: true
                 },
                 Map.new(opts)
               )
             )

    File.read!(Path.join(out_dir, "c/elmc_generated.c"))
  end
end
