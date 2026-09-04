defmodule Elmc.PlanConstructCatalogTest do
  @moduledoc """
  One snippet compile covering common IR constructs. Prefer this over a new
  full-template compile when adding Verify / C-shape coverage.
  """

  use ExUnit.Case, async: false

  alias Elmc.Backend.C.Ast.Lint, as: AstLint
  alias Elmc.Backend.Plan.Lower.Function, as: PlanFunction
  alias Elmc.Backend.Plan.Verify
  alias Elmc.TestSupport.SnippetProject

  @moduletag timeout: 180_000

  test "construct catalog compiles, verifies, and RC-lints" do
    {result, generated} =
      SnippetProject.compile_checked!(catalog_source(),
        name: "construct_catalog",
        keep_ir: true,
        compile: %{plan_ir_mode: :primary, plan_ir_strict: true},
        out_dir: Path.expand("tmp/construct_catalog", __DIR__)
      )

    assert result
    AstLint.run_source!(generated)

    refute Enum.any?(
             stream_fallback_diagnostics(result),
             &(&1["code"] == "plan_stream_fallback" or &1[:code] == "plan_stream_fallback")
           )

    # Value-return Float ABI: boxed call sites assign `double tmp = fn(…)`,
    # never `Rc = fn(&tmp, …)` against a `static double` prototype.
    refute generated =~ ~r/Rc = elmc_fn_Main_identityFloat\(/
    assert generated =~ "elmc_as_float(x)"
    refute generated =~ ~r/elmc_as_int\(a\) \+ elmc_as_int\(b\)/
    assert generated =~ "elmc_as_float(a)"

    decl_map = Elmc.Backend.CCodegen.IRQueries.function_decl_map(result.ir)

    for {{mod, name}, decl} <- decl_map,
        mod == "Main",
        name not in ["main"] do
      case PlanFunction.lower(decl, mod, decl_map, rc_required: true) do
        {:ok, plan} ->
          assert :ok = Verify.run(plan), "#{mod}.#{name} failed Verify"

        :unsupported ->
          :ok

        {:error, reason} ->
          flunk("#{mod}.#{name} lower error: #{inspect(reason)}")
      end
    end
  end

  defp catalog_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color
    import Platform.Cmd
    import Platform.Sub


    type alias Model =
        { n : Int
        , flag : Bool
        , label : Maybe String
        , f : Float
        }


    type Msg
        = Tick
        | Set Int
        | Toggle


    identityInt : Int -> Int
    identityInt x =
        x


    identityBool : Bool -> Bool
    identityBool x =
        x


    identityFloat : Float -> Float
    identityFloat x =
        x


    addFloat : Float -> Float -> Float
    addFloat a b =
        a + b


    clampN : Int -> Int
    clampN x =
        Basics.clamp 0 99 x


    maybeLabel : Maybe String -> String
    maybeLabel m =
        Maybe.withDefault "" m


    addPair : Int -> Int -> Int
    addPair a b =
        a + b


    pick : Bool -> Int -> Int -> Int
    pick flag a b =
        if flag then
            a
        else
            b


    view : Model -> Ui.UiNode
    view model =
        Ui.toUiNode
            [ Ui.rect { x = 0, y = 0, w = 10, h = 10 } Color.black
            ]


    main =
        Platform.application
            { init = init
            , update = update
            , subscriptions = subscriptions
            , view = view
            }


    init _ =
        ( { n = 0, flag = False, label = Nothing, f = 0.0 }
        , Cmd.none
        )


    update msg model =
        case msg of
            Tick ->
                ( { model
                    | n = identityInt (model.n + 1)
                    , flag = identityBool model.flag
                    , f = addFloat (identityFloat model.f) 1.0
                  }
                , Cmd.none
                )

            Set x ->
                ( { model | n = clampN x }, Cmd.none )

            Toggle ->
                ( { model | flag = not model.flag, label = Just "on" }, Cmd.none )


    subscriptions _ =
        Sub.none
    """
  end

  defp stream_fallback_diagnostics(result) do
    Enum.concat([
      Map.get(result, :layout_coercion_diagnostics, []),
      Map.get(result, :informational_diagnostics, []),
      Map.get(result, :blocking_diagnostics, [])
    ])
  end
end
