defmodule Elmc.TimeEveryPebbleFeatureTest do
  use ExUnit.Case

  test "Time.every enables Pebble tick event feature flag" do
    uniq = System.unique_integer([:positive])
    project_dir = Path.join(System.tmp_dir!(), "elmc_time_every_#{uniq}")
    out_dir = Path.join(project_dir, ".out")
    src_dir = Path.join(project_dir, "src")

    elm_time_src =
      Path.expand("../../ide/priv/internal_packages/elm-time/src", __DIR__)

    File.rm_rf!(project_dir)
    File.mkdir_p!(src_dir)

    elm_json = %{
      "type" => "application",
      "source-directories" => ["src", elm_time_src],
      "elm-version" => "0.19.1",
      "dependencies" => %{
        "direct" => %{
          "elm/core" => "1.0.5",
          "elm/time" => "1.0.0"
        },
        "indirect" => %{}
      },
      "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
    }

    File.write!(Path.join(project_dir, "elm.json"), Jason.encode!(elm_json, pretty: true))

    File.write!(
      Path.join(src_dir, "Main.elm"),
      """
      module Main exposing (main)

      import Platform
      import Time

      type alias Model =
          Int

      type Msg
          = Tick Time.Posix

      init : () -> ( Model, Cmd Msg )
      init _ =
          ( 0, Cmd.none )

      update : Msg -> Model -> ( Model, Cmd Msg )
      update msg model =
          case msg of
              Tick _ ->
                  ( model, Cmd.none )

      subscriptions : Model -> Sub Msg
      subscriptions _ =
          Time.every 1000 Tick

      main : Program () Model Msg
      main =
          Platform.worker
              { init = init
              , update = update
              , subscriptions = subscriptions
              }
      """
    )

    assert {:ok, _result} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    header = File.read!(Path.join(out_dir, "c/elmc_pebble.h"))
    assert header =~ "#define ELMC_PEBBLE_FEATURE_TICK_EVENTS 1"
  end
end
