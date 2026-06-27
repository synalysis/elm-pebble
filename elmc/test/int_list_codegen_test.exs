defmodule Elmc.IntListCodegenTest do
  use ExUnit.Case, async: true

  test "List.repeat n 0 emits compact ELMC_TAG_INT_LIST" do
    source = """
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
    """

    project_dir = Path.expand("tmp/int_list_repeat_zero", __DIR__)
    out_dir = Path.expand("tmp/int_list_repeat_zero_codegen", __DIR__)
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

    assert generated_c =~ "ELMC_TAG_INT_LIST"
    assert generated_c =~ "elmc_immortal_list_Main_blankRow_values[4]"
    refute generated_c =~ "elmc_immortal_list_Main_blankRow_cells["
    refute generated_c =~ "list_repeat_i_"
  end

  test "static int list literal uses immortal int list prelude" do
    source = """
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
    """

    project_dir = Path.expand("tmp/int_list_literal", __DIR__)
    out_dir = Path.expand("tmp/int_list_literal_codegen", __DIR__)
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

    assert generated_c =~ "ELMC_TAG_INT_LIST"
    assert generated_c =~ "elmc_immortal_list_Main_row_values[4]"
    refute generated_c =~ "list_repeat_i_"
  end
end
