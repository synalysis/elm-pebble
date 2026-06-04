defmodule Elmc.BundledPebbleSurfaceCodegenTest do
  use ExUnit.Case

  @source """
  module Main exposing (main)

  import Pebble.Health as Health
  import Pebble.Platform as Platform
  import Platform

  type alias Model =
      { reasonOk : Bool
      , stepsCmd : Bool
      }

  type Msg
      = StepsToday Int
      | HealthSupported Bool
      | Noop

  init : LaunchContext -> ( Model, Cmd Msg )
  init context =
      ( { reasonOk = context.reason == Platform.LaunchWakeup
        , stepsCmd = False
        }
      , Cmd.batch
          [ Health.supported HealthSupported
          , Health.sumToday Health.StepCount StepsToday
          ]
      )

  update : Msg -> Model -> ( Model, Cmd Msg )
  update msg model =
      case msg of
          StepsToday _ ->
              ( { model | stepsCmd = True }, Cmd.none )

          HealthSupported _ ->
              ( model, Cmd.none )

          Noop ->
              ( model, Cmd.none )

  view _ =
      Platform.worker { init = init, update = update, view = \\_ -> [] }
  """

  test "bundled Pebble Platform and Health surface lower without missing C symbols" do
    project_dir = Path.expand("tmp/bundled_pebble_surface_project", __DIR__)
    out_dir = Path.expand("tmp/bundled_pebble_surface_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.mkdir_p!(Path.join(project_dir, "vendor"))

    bundled_src =
      Path.expand("../../ide/priv/bundled_elm/pebble-watch-src", __DIR__)

    File.cp_r!(bundled_src, Path.join(project_dir, "vendor/pebble-watch-src"))

    File.write!(
      Path.join(project_dir, "elm.json"),
      """
      {
        "type": "application",
        "source-directories": [
          "src",
          "vendor/pebble-watch-src"
        ],
        "elm-version": "0.19.1",
        "dependencies": {
          "direct": {
            "elm/json": "1.1.3",
            "elm/time": "1.0.0"
          },
          "indirect": {}
        },
        "test-dependencies": {
          "direct": {},
          "indirect": {}
        }
      }
      """
    )

    File.write!(Path.join(project_dir, "src/Main.elm"), @source)

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    init_fn =
      generated_c
      |> String.split("ElmcValue *elmc_fn_Main_init(ElmcValue ** const args, const int argc) {", parts: 2)
      |> Enum.at(1, "")
      |> String.split("ElmcValue *elmc_fn_Main_update(ElmcValue ** const args, const int argc) {", parts: 2)
      |> hd()

    refute init_fn =~ "elmc_fn_Pebble_Platform_LaunchWakeup("
    refute init_fn =~ "elmc_fn_Pebble_Health_supported("
    refute init_fn =~ "elmc_fn_Pebble_Health_sumToday("
    refute init_fn =~ "elmc_fn_Pebble_Health_StepCount("

    assert init_fn =~ "elmc_new_int(4)"
    assert init_fn =~ "elmc_list_from_values_take(list_items_28, 2)"
  end
end
