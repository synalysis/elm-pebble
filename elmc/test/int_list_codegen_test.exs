defmodule Elmc.IntListCodegenTest do
  use ExUnit.Case, async: true

  alias Elmc.Test.CCodegenExtract

  defp compile_main!(source, project_name) do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/#{project_name}", __DIR__)
    out_dir = Path.expand("tmp/#{project_name}_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(source_fixture, project_dir)
    File.write!(Path.join(project_dir, "src/Main.elm"), source)

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true
             })

    File.read!(Path.join(out_dir, "c/elmc_generated.c"))
  end

  test "List.repeat n 0 emits plan compact int array list" do
    generated_c =
      compile_main!(
        """
        module Main exposing (main)

        import Json.Decode as Decode
        import Pebble.Platform as Platform
        import Pebble.Ui as Ui
        import Pebble.Ui.Color as Color

        blankRow : List Int
        blankRow =
            List.repeat 4 0

        init _ = ( { n = List.length blankRow }, Platform.Cmd.none )
        update _ m = ( m, Platform.Cmd.none )
        view m = Ui.toUiNode [ Ui.clear Color.white, Ui.text (String.fromInt m.n) ]
        subscriptions _ = Platform.Sub.none
        main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
        """,
        "int_list_repeat_zero"
      )

    blank_row_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_blankRow")

    assert blank_row_body =~ "plan block"
    assert blank_row_body =~ "plan_list_int_values_"
    assert blank_row_body =~ "elmc_list_from_int_array"
    refute blank_row_body =~ "list_repeat_i_"
  end

  test "static int list literal uses plan compact int array list" do
    generated_c =
      compile_main!(
        """
        module Main exposing (main)

        import Json.Decode as Decode
        import Pebble.Platform as Platform
        import Pebble.Ui as Ui
        import Pebble.Ui.Color as Color

        row : List Int
        row =
            [ 2, 2, 2, 2 ]

        init _ = ( { n = List.length row }, Platform.Cmd.none )
        update _ m = ( m, Platform.Cmd.none )
        view m = Ui.toUiNode [ Ui.clear Color.white, Ui.text (String.fromInt m.n) ]
        subscriptions _ = Platform.Sub.none
        main = Platform.application { init = init, update = update, view = view, subscriptions = subscriptions }
        """,
        "int_list_literal"
      )

    row_body = CCodegenExtract.fn_body(generated_c, "elmc_fn_Main_row")

    assert row_body =~ "plan block"
    assert row_body =~ "plan_list_int_values_"
    assert row_body =~ "elmc_list_from_int_array"
    refute row_body =~ "list_repeat_i_"
  end
end
