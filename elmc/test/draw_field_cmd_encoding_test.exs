defmodule Elmc.DrawFieldCmdEncodingTest do
  use ExUnit.Case

  alias Elmc.Backend.CCodegen.Emit
  alias Elmc.Backend.CCodegen.SpecialValues
  alias Elmc.Backend.Pebble.Kinds

  test "fillCircle with point center encodes render op kind not runtime command id" do
    center = %{op: :var, name: "center"}
    radius = %{op: :int_literal, value: 3}
    color = %{op: :int_literal, value: 1}

    expr =
      SpecialValues.special_value_from_target("Pebble.Ui.fillCircle", [center, radius, color])

    assert %{op: :render_cmd, kind: %{op: :c_int_expr, value: "ELMC_RENDER_OP_FILL_CIRCLE"}} =
             expr

    refute inspect(expr) =~ "GET_CLOCK_STYLE"
  end

  test "fillCircle with int literals compiles to elmc_render_cmd6 not tuple2 chain" do
    source = """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui

    type alias Model = ()

    type Msg = Noop

    init _ = ( (), Platform.Cmd.none )

    update _ model = ( model, Platform.Cmd.none )

    subscriptions _ = Platform.Sub.none

    view _ =
        Ui.toUiNode [ Ui.fillCircle 10 20 3 1 ]

    main =
        Platform.application
            { init = init, update = update, view = view, subscriptions = subscriptions }
    """

    project_dir = Path.expand("tmp/render_cmd_codegen", __DIR__)
    out_dir = Path.expand("tmp/render_cmd_codegen_out", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

    assert {:ok, _} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "elmc_render_cmd6(ELMC_RENDER_OP_FILL_CIRCLE, 10, 20, 3, 1, 0, 0)"
    refute generated_c =~ ~r/ELMC_RENDER_OP_FILL_CIRCLE[\s\S]{0,300}elmc_new_int\(&owned/
  end

  test "generated render-op defines cover every draw kind id" do
    defines = Emit.generated_magic_number_defines()

    for {kind, id} <- Kinds.draw_kinds() do
      macro = kind |> Atom.to_string() |> String.upcase()
      assert defines =~ "#define ELMC_RENDER_OP_#{macro} #{id}"
    end
  end
end
