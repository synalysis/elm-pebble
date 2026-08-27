defmodule Elmc.DirectRenderJustLinePayloadTest do
  use ExUnit.Case, async: false

  @moduletag timeout: 180_000

  alias Elmc.Test.CCodegenExtract
  alias Elmc.TestSupport.GeneratedCLint
  alias Elmc.TestSupport.SnippetProject

  test "Just record bind is used for nested line endpoints, not an unbound C name" do
    source = """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color


    type alias Point =
        { x : Int, y : Int }


    type alias Hands =
        { tip : Point, tail : Point }


    type alias Model =
        { center : Point
        , maybeHands : Maybe Hands
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
        ( { center = { x = 72, y = 84 }
          , maybeHands = Just { tip = { x = 72, y = 20 }, tail = { x = 72, y = 100 } }
          }
        , Cmd.none
        )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view model =
        Ui.toUiNode (handOps model.center model.maybeHands)


    handOps : Point -> Maybe Hands -> List Ui.RenderOp
    handOps center maybeHands =
        case maybeHands of
            Nothing ->
                []

            Just hands ->
                [ Ui.line center hands.tip Color.black
                , Ui.line center hands.tail Color.black
                ]
    """

    {result, generated_c} =
      SnippetProject.compile_checked!(source,
        name: "just_hands_line_payload",
        compile: %{
          direct_render_only: true,
          prune_runtime: true,
          prune_native_wrappers: true,
          plan_ir_mode: :primary
        },
        out_dir: Path.expand("tmp/just_hands_line_payload_codegen", __DIR__)
      )

    fallbacks = GeneratedCLint.stream_fallbacks(result.layout_coercion_diagnostics)

    assert fallbacks == []
    assert generated_c =~ "elmc_maybe_or_tuple_just_payload_borrow" or
             generated_c =~ "elmc_maybe_just_payload",
           "Just payload must be peeled in Plan stream or runtime helper C"

    body =
      [
        "elmc_fn_Main_handOps_commands_append_native",
        "elmc_fn_Main_handOps_commands_append",
        "elmc_fn_Main_view_commands_append"
      ]
      |> Enum.map(&CCodegenExtract.fn_impl_body(generated_c, &1))
      |> Enum.find("", &(&1 != ""))

    assert body != "", "expected a commands_append body for handOps/view"

    refute body =~ ~r/\bELMC_RECORD_GET_INDEX\(\s*hands\s*,/,
           "Just payload field reads must not use an undeclared `hands` C identifier"

    assert body =~ "elmc_maybe_or_tuple_just_payload_borrow" or
             body =~ "elmc_maybe_just_payload",
           "Just record field reads must peel the Maybe payload"
  end
end
