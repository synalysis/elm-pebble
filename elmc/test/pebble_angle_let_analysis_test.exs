defmodule Elmc.PebbleAngleLetAnalysisTest do
  use ExUnit.Case

  alias ElmEx.Frontend.GeneratedParser
  alias ElmEx.Frontend.Project
  alias ElmEx.IR.Lowerer
  alias ElmEx.IR.PipeChain
  alias Elmc.Backend.CCodegen.Native.BindingAnalysis
  alias Elmc.Backend.CCodegen.Native.UsageAnalysis

  test "trig let value is a pebble angle expression" do
    source = """
    module Main exposing (trigLen)

    trigLen angle radius =
        let
            theta =
                toFloat angle * 2 * Basics.pi / 65536
        in
        Basics.round (Basics.sin theta * Basics.toFloat radius)
    """

    {:ok, module} = GeneratedParser.parse_source("Main.elm", source)
    project = %Project{project_dir: ".", elm_json: %{}, modules: [module]}
    {:ok, ir0} = Lowerer.lower_project(project)
    ir = PipeChain.desugar_project(ir0)

    decl =
      ir.modules
      |> Enum.flat_map(& &1.declarations)
      |> Enum.find(&(&1.name == "trigLen"))

    %{op: :let_in, name: name, value_expr: value_expr, in_expr: in_expr} = decl.expr

    assert BindingAnalysis.pebble_angle_expr?(value_expr),
           "lowered value_expr: #{inspect(value_expr, limit: 12)}"

    assert BindingAnalysis.reference_count(name, in_expr) ==
             BindingAnalysis.pebble_angle_optimized_reference_count(name, in_expr)

    assert UsageAnalysis.pebble_angle_let?(name, value_expr, in_expr)
  end

  test "trigLen IR after full compile still has pebble angle let" do
    project_dir = Path.expand("tmp/pebble_trig_ir_probe", __DIR__)
    File.rm_rf!(project_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), """
    module Main exposing (trigLen)
    trigLen angle radius =
        let
            theta =
                toFloat angle * 2 * Basics.pi / 65536
        in
        Basics.round (Basics.sin theta * Basics.toFloat radius)
    """)
    File.cp!(Path.expand("fixtures/simple_project/elm.json", __DIR__), Path.join(project_dir, "elm.json"))

    assert {:ok, %{ir: ir}} =
             Elmc.compile(project_dir, %{
               out_dir: Path.expand("tmp/pebble_trig_ir_probe_out", __DIR__),
               entry_module: "Main",
               strip_dead_code: false
             })

    decl =
      ir.modules
      |> Enum.flat_map(& &1.declarations)
      |> Enum.find(&(&1.name == "trigLen"))

    %{op: :let_in, name: name, value_expr: value_expr, in_expr: in_expr} = decl.expr

    assert UsageAnalysis.pebble_angle_let?(name, value_expr, in_expr)
  end

  test "trigLen lowers as native int return for pebble trig fusion" do
    project_dir = Path.expand("tmp/pebble_trig_return_kind", __DIR__)
    out_dir = Path.expand("tmp/pebble_trig_return_kind_out", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), """
    module Main exposing (main)

    import Basics
    import Pebble.Platform as Platform

    type alias Model = ()

    type Msg = Noop

    init _ = ( trigLen 0 10, Platform.Cmd.none )
    update _ m = ( m, Platform.Cmd.none )
    subscriptions _ = Platform.Sub.none

    trigLen : Int -> Int -> Int
    trigLen angle radius =
        let
            theta =
                toFloat angle * 2 * Basics.pi / 65536
        in
        Basics.round (Basics.sin theta * Basics.toFloat radius)

    view _ = Platform.Cmd.none

    main = Platform.application { init = init, update = update, view = \\ _ -> Platform.Cmd.none, subscriptions = subscriptions }
    """)
    File.cp!(Path.expand("fixtures/simple_project/elm.json", __DIR__), Path.join(project_dir, "elm.json"))

    assert {:ok, %{ir: ir}} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               pebble_int32: true,
               strip_dead_code: false
             })

    decl =
      ir.modules
      |> Enum.flat_map(& &1.declarations)
      |> Enum.find(&(&1.name == "trigLen"))

    decl_map = Elmc.Backend.CCodegen.IRQueries.function_decl_map(ir)

    assert Elmc.Backend.CCodegen.Native.FunctionCall.native_scalar_return?(
             decl,
             "Main",
             decl_map
           )

    assert Elmc.Backend.CCodegen.Native.FunctionCall.native_scalar_fn?(decl, "Main", decl_map)

    assert Elmc.Backend.CCodegen.Native.FunctionCall.return_kind(decl, "Main", decl_map) ==
             :native_int
  end
end
