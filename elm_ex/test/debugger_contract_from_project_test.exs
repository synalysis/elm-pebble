defmodule ElmEx.DebuggerContractFromProjectTest do
  use ExUnit.Case, async: true

  alias ElmEx.DebuggerContract
  alias ElmEx.Frontend.GeneratedParser
  alias ElmEx.Frontend.Project

  @subs_source """
  module Main exposing (..)

  import Pebble.Events as Events

  type Msg
      = Tick

  subscriptions _ =
      Events.batch [ Events.onSecondChange Tick ]

  init _ =
      ( {}, Cmd.none )

  update _ m =
      m

  view _ =
      X.y []
  """

  test "from_project builds contract without a second parse" do
    assert {:ok, mod} = GeneratedParser.parse_source("Main.elm", @subs_source)

    project = %Project{
      project_dir: "/tmp/test-project",
      elm_json: %{"source-directories" => ["src"]},
      modules: [mod]
    }

    assert {:ok, %{"debugger_contract" => contract}} = DebuggerContract.from_project(project)

    assert is_map(contract)
    assert contract["source"] == "project_module"
    assert Enum.any?(contract["subscription_calls"] || [], &is_map/1)
  end

  test "update_ctor_model_fields maps msg params to model fields" do
    source = """
    module Main exposing (..)

    type alias Model = { on : Bool }

    type Msg = ClockStyle24h Bool

    init _ = ( { on = False }, Cmd.none )

    update msg model =
        case msg of
            ClockStyle24h value ->
                ( { model | on = value }, Cmd.none )

    view _ = Html.text "x"
    """

    assert {:ok, mod} = GeneratedParser.parse_source("Main.elm", source)

    assert {:ok, %{"debugger_contract" => contract}} =
             DebuggerContract.from_project(%Project{
               project_dir: "/tmp/test",
               elm_json: %{"source-directories" => ["src"]},
               modules: [mod]
             })

    assert contract["update_ctor_model_fields"] == %{"ClockStyle24h" => %{"value" => "on"}}
  end

  test "contract_payload accepts bare contract map" do
    inner = %{"msg_constructors" => ["A"]}
    assert DebuggerContract.contract_payload(inner) == inner
    assert DebuggerContract.contract_payload(%{"elm_introspect" => inner}) == inner
  end
end
