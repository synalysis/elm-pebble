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
        compile: %{plan_ir_mode: :primary, plan_ir_strict: true},
        out_dir: Path.expand("tmp/construct_catalog", __DIR__)
      )

    assert result
    AstLint.run_source!(generated)

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


    type alias Model =
        { n : Int
        , flag : Bool
        , label : Maybe String
        }


    type Msg
        = Tick
        | Set Int
        | Toggle


    identityInt : Int -> Int
    identityInt x =
        x


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


    view : Model -> Ui.Node Msg
    view model =
        Ui.toUiNode
            [ Ui.rect Color.black 0 0 10 10
            ]


    main =
        Platform.application
            { init = init
            , update = update
            , subscriptions = subscriptions
            , view = view
            }


    init _ =
        ( { n = 0, flag = False, label = Nothing }
        , Cmd.none
        )


    update msg model =
        case msg of
            Tick ->
                ( { model | n = identityInt (model.n + 1) }, Cmd.none )

            Set x ->
                ( { model | n = clampN x }, Cmd.none )

            Toggle ->
                ( { model | flag = not model.flag, label = Just "on" }, Cmd.none )


    subscriptions _ =
        Sub.none
    """
  end
end
