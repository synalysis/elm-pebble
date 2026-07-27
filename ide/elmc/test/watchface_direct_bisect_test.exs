defmodule Elmc.WatchfaceDirectBisectTest do
  use ExUnit.Case, async: false

  @fixture Path.expand("fixtures/simple_project", __DIR__)

  defp compile_direct!(source) do
    project_dir = Path.expand("tmp/watchface_bisect_#{:erlang.unique_integer([:positive])}", __DIR__)
    out_dir = project_dir <> "_out"
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(@fixture, project_dir)
    File.write!(Path.join(project_dir, "src/Main.elm"), source)

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               direct_render_only: true,
               prune_runtime: true,
               prune_native_wrappers: true
             })

    out_dir
  end

  defp header do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color
    import Pebble.Ui.Resources as Resources
    import String


    type alias Model =
        { screenW : Int
        , screenH : Int
        }


    type Msg
        = NoOp


    main =
        Platform.application
            { init = init
            , update = update
            , subscriptions = subscriptions
            , view = view
            }


    init _ =
        ( { screenW = 144, screenH = 168 }, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    """
  end

  test "direct faceOps with drawDial fillCircle and drawOuterScale" do
    compile_direct!(
      header() <>
        """
        view model =
            Ui.toUiNode (faceOps model)


        faceOps model =
            let
                cx =
                    model.screenW // 2

                cy =
                    model.screenH // 2

                radius =
                    (min model.screenW model.screenH // 2) - 22

                dial =
                    drawDial model cx cy radius
            in
            [ Ui.clear Color.black ]
                ++ dial


        drawDial model cx cy radius =
            [ Ui.fillCircle { x = cx, y = cy } radius Color.black ]
                ++ drawOuterScale cx cy radius


        drawOuterScale cx cy radius =
            List.concatMap
                (\\hour ->
                    [ Ui.line { x = cx, y = cy } { x = cx, y = cy + 5 } Color.white ]
                )
                (List.range 0 2)
        """
    )
  end

  test "direct drawDial with fillRadial sun arc" do
    compile_direct!(
      header() <>
        """
        view model =
            Ui.toUiNode (drawDial model 72 84 60)


        drawDial model cx cy radius =
            let
                sunBounds =
                    square cx cy (radius - 5)
            in
            [ Ui.group
                (Ui.context
                    [ Ui.fillColor Color.chromeYellow, Ui.strokeColor Color.chromeYellow ]
                    [ Ui.fillRadial sunBounds 0 32768 ]
                )
            ]


        square cx cy radius =
            { x = cx - radius, y = cy - radius, w = radius * 2, h = radius * 2 }
        """
    )
  end

  test "direct drawDial with timeString textAt" do
    compile_direct!(
      header() <>
        """
        view model =
            Ui.toUiNode (drawDial model)


        drawDial model =
            let
                cx =
                    model.screenW // 2

                cy =
                    model.screenH // 2
            in
            [ textAt Color.white { x = cx - 31, y = cy - 40, w = 64, h = 18 } (timeString model)
            ]


        textAt color bounds value =
            Ui.group
                (Ui.context
                    [ Ui.textColor color ]
                    [ Ui.text Resources.DefaultFont Ui.defaultTextOptions bounds value ]
                )


        timeString model =
            "12:00"
        """
    )
  end

  test "direct drawDial with pointAt hand line" do
    compile_direct!(
      header() <>
        """
        view model =
            Ui.toUiNode (drawDial model 72 84 60)


        drawDial model cx cy radius =
            [ Ui.line { x = cx, y = cy } (pointAt cx cy (radius - 10) 0) Color.white ]


        pointAt cx cy radius angle =
            { x = cx + radius, y = cy + radius }
        """
    )
  end

  test "direct Ui.group with bare command list" do
    out_dir =
      compile_direct!(
        header() <>
          """
          view model =
              Ui.toUiNode (mountLines model)


          mountLines model =
              Ui.group
                  [ Ui.line { x = 4, y = 20 } { x = 14, y = 6 } Color.white
                  , Ui.line { x = 14, y = 6 } { x = 22, y = 20 } Color.white
                  ]
          """
      )

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    view_body = generated_c |> String.split("elmc_fn_Main_view_commands_append", parts: 2) |> Enum.at(1, "")

    assert view_body =~ "elmc_scene_writer_push_cmd"
    refute view_body =~ "elmc_fn_Pebble_Ui_toUiNode"
  end

  test "direct inline skips unused trailing render helper params" do
    out_dir =
      compile_direct!(
        header() <>
          """
          view model =
              Ui.toUiNode (drawBadge model)


          drawBadge model =
              case model.moonPhaseE6 of
                  Just phase ->
                      badge 10 10 8 phase

                  Nothing ->
                      []


          badge cx cy radius _ _unusedPhase =
              [ Ui.fillCircle { x = cx, y = cy } radius Color.lightGray ]
          """
      )

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    assert generated_c =~ "elmc_fn_Main_view_commands_append"
    refute generated_c =~ "direct Pebble command inline generation failed"
  end

end
