defmodule Elmc.DirectRenderCodegenGatesTest do
  @moduledoc """
  Host-typecheck + record-base lint for direct-render IR shapes that historically
  slipped through plan-only / string-assert tests:

  * `Just bind` constructor (name on `arg_pattern`, no `:bind`)
  * bare-var Maybe unwrap
  * `Ok` payload used as a line endpoint
  * native `(Int, Int)` helper consumed from view
  """

  use ExUnit.Case, async: false

  @moduletag timeout: 180_000

  alias Elmc.Test.CCodegenExtract
  alias Elmc.TestSupport.SnippetProject

  @snippet_opts %{
    direct_render_only: true,
    prune_runtime: true,
    prune_native_wrappers: true,
    plan_ir_mode: :primary
  }

  test "Just constructor + nested Point line endpoints typecheck" do
    {_result, generated} =
      compile_gate!("gate_just_nested_point", """
      #{header()}

      type alias Model =
          { center : Point
          , maybePts : Maybe Pts
          }


      view model =
          Ui.toUiNode (drawOps model.center model.maybePts)


      drawOps : Point -> Maybe Pts -> List Ui.RenderOp
      drawOps center maybePts =
          case maybePts of
              Nothing ->
                  []

              Just payload ->
                  [ Ui.line center payload.tip Color.black
                  , Ui.line center payload.tail Color.black
                  ]

      #{footer("{ center = { x = 72, y = 84 }, maybePts = Just { tip = { x = 72, y = 20 }, tail = { x = 72, y = 100 } } }")}
      """)

    body = commands_append_body!(generated)
    refute body =~ ~r/\bELMC_RECORD_GET_INDEX\(\s*payload\s*,/
    assert body =~ "elmc_maybe_or_tuple_just_payload_borrow" or body =~ "elmc_maybe_is_just"
  end

  test "bare-var Maybe + nested Point line endpoints typecheck" do
    {_result, generated} =
      compile_gate!("gate_bare_var_nested_point", """
      #{header()}

      type alias Model =
          { center : Point
          , maybePts : Maybe Pts
          }


      view model =
          Ui.toUiNode (drawOps model.center model.maybePts)


      drawOps : Point -> Maybe Pts -> List Ui.RenderOp
      drawOps center maybePts =
          case maybePts of
              Nothing ->
                  []

              payload ->
                  [ Ui.line center payload.tip Color.black ]

      #{footer("{ center = { x = 72, y = 84 }, maybePts = Just { tip = { x = 1, y = 2 }, tail = { x = 3, y = 4 } } }")}
      """)

    body = commands_append_body!(generated)
    refute body =~ ~r/\bELMC_RECORD_GET_INDEX\(\s*payload\s*,/
  end

  test "Ok payload Point used as a line endpoint typechecks" do
    {_result, generated} =
      compile_gate!("gate_ok_point_line", """
      #{header()}

      type alias Model =
          { center : Point
          , maybePt : Result String Point
          }


      view model =
          Ui.toUiNode (drawOps model.center model.maybePt)


      drawOps : Point -> Result String Point -> List Ui.RenderOp
      drawOps center maybePt =
          case maybePt of
              Err _ ->
                  []

              Ok tip ->
                  [ Ui.line center tip Color.black ]

      #{footer("{ center = { x = 72, y = 84 }, maybePt = Ok { x = 10, y = 20 } }")}
      """)

    body = commands_append_body!(generated)
    refute body =~ ~r/\bELMC_RECORD_GET_INDEX\(\s*tip\s*,/
  end

  test "native Int pair helper used from view typechecks" do
    {_result, generated} =
      compile_gate!("gate_native_int_pair_view", """
      #{header()}

      type alias Model =
          { center : Point
          , tick : Int
          }


      unit4 : Int -> ( Int, Int )
      unit4 index =
          case modBy 4 index of
              0 ->
                  ( 0, -10 )

              1 ->
                  ( 10, 0 )

              2 ->
                  ( 0, 10 )

              _ ->
                  ( -10, 0 )


      view model =
          Ui.toUiNode (drawOps model.center model.tick)


      drawOps : Point -> Int -> List Ui.RenderOp
      drawOps center tick =
          let
              ( dx, dy ) =
                  unit4 tick
          in
          [ Ui.line center { x = center.x + dx, y = center.y + dy } Color.black ]

      #{footer("{ center = { x = 72, y = 84 }, tick = 1 }")}
      """)

    assert generated =~ "elmc_fn_Main_unit4"
    refute generated =~ ~r/static ElmcValue \*elmc_fn_Main_unit4\s*\(\s*elmc_int_t/
    assert generated =~ ~r/elmc_fn_Main_unit4\(\s*&native_pair_\d+_0,\s*&native_pair_\d+_1,/
  end

  test "plan_stream_fallback diagnostics stay warnings, never silent errors" do
    {_result, generated} =
      compile_gate!("gate_stream_fallback_visible", """
      #{header()}

      type alias Model =
          { center : Point
          , maybePts : Maybe Pts
          }


      view model =
          Ui.toUiNode (drawOps model.center model.maybePts)


      drawOps : Point -> Maybe Pts -> List Ui.RenderOp
      drawOps center maybePts =
          case maybePts of
              Nothing ->
                  []

              Just payload ->
                  [ Ui.line center payload.tip Color.black ]

      #{footer("{ center = { x = 72, y = 84 }, maybePts = Just { tip = { x = 1, y = 2 }, tail = { x = 3, y = 4 } } }")}
      """)

    assert commands_append_body!(generated) != ""
    refute generated =~ ~r/\bELMC_RECORD_GET_INDEX\(\s*payload\s*,/
  end

  defp compile_gate!(name, source) do
    out_dir = Path.expand("tmp/#{name}_codegen", __DIR__)

    SnippetProject.compile_checked!(source,
      name: name,
      compile: @snippet_opts,
      out_dir: out_dir
    )
  end

  defp commands_append_body!(generated_c) do
    [
      "elmc_fn_Main_drawOps_commands_append_native",
      "elmc_fn_Main_drawOps_commands_append",
      "elmc_fn_Main_view_commands_append"
    ]
    |> Enum.map(&CCodegenExtract.fn_impl_body(generated_c, &1))
    |> Enum.find("", &(&1 != ""))
  end

  defp header do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color


    type alias Point =
        { x : Int, y : Int }


    type alias Pts =
        { tip : Point, tail : Point }


    type Msg
        = NoOp
    """
  end

  defp footer(init_record) do
    """
    main =
        Platform.application
            { init = init
            , update = update
            , subscriptions = subscriptions
            , view = view
            }


    init _ =
        ( #{init_record}
        , Cmd.none
        )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none
    """
  end
end
