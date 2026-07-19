defmodule ElmEx.Frontend.Pretty.ModuleNormalizeTest do
  use ExUnit.Case, async: true

  alias ElmEx.Frontend.{GeneratedParser, Pretty}
  alias ElmEx.Frontend.Pretty.ModuleNormalize

  @module_source """
  module Main exposing (..)

  type alias Base =
      { x | on : Bool
      , label : String
      , count : Int
      }

  type Msg
      = Tick
      | Set Bool

  init _ =
      ( {}, Cmd.none )

  update msg model =
      case msg of
          Tick ->
              ( model, Cmd.none )
          Set value ->
              ( { model | on = value }, Cmd.none )
  """

  test "round_trip_module_ast? preserves types and function bodies" do
    assert Pretty.round_trip_module_ast?("Main.elm", @module_source)
    assert Pretty.round_trip_module?("Main.elm", @module_source)
  end

  test "ModuleNormalize tracks extensible type alias base" do
    assert {:ok, mod} = GeneratedParser.parse_source("Main.elm", @module_source)

    alias_decl = Enum.find(mod.declarations, &(&1.kind == :type_alias))
    assert alias_decl.extensible_base == "x"
    assert alias_decl.field_types == %{"on" => "Bool", "label" => "String", "count" => "Int"}

    formatted = Pretty.format_module(mod)
    assert formatted =~ "{ x | on : Bool"

    assert {:ok, reparsed} = GeneratedParser.parse_source("Main.elm", formatted)
    assert ModuleNormalize.equivalent?(mod, reparsed)
  end

  test "round_trip_module_ast? preserves type alias synonyms" do
    source = """
    module Main exposing (main)

    type alias Model = String

    main : Model
    main =
        "hello"
    """

    assert Pretty.round_trip_module_ast?("Main.elm", source)

    assert {:ok, _mod} = GeneratedParser.parse_source("Main.elm", source)
    assert {:ok, formatted} = Pretty.format_module_source("Main.elm", source)
    assert formatted =~ "type alias Model = String"
  end

  test "round_trip_module_ast? preserves subscriptions with inline if" do
    source = """
    module Main exposing (..)

    type Msg
        = Tick

    subscriptions model =
        if model.on then
            Sub.none
        else
            Sub.none

    update msg model =
        ( model, Cmd.none )
    """

    assert Pretty.round_trip_module_ast?("Main.elm", source)
  end
end
