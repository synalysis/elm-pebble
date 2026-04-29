defmodule Ide.Debugger.ElmIntrospectTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.ElmIntrospect

  @mini_elm """
  module Snap exposing (..)

  type Msg
      = Inc
      | Dec

  init _ =
      ( { count = 0, note = Nothing }, Cmd.none )

  view model =
      PebbleUi.windowStack        [ PebbleUi.window 1
              [ PebbleUi.textLabelWithFont UiResources.DefaultFont 0 0 WaitingForCompanion ]
          ]
  """

  @numeric_view_elm """
  module NumericView exposing (..)

  type alias Model =
      { hhmm : Int }

  type Msg
      = Tick

  init _ =
      ( { hhmm = 1234 }, Cmd.none )

  view model =
      PebbleUi.windowStack
          [ PebbleUi.window 1
              [ PebbleUi.canvasLayer 1
                  [ PebbleUi.clear 0
                  , PebbleUi.roundRect 16 56 112 56 8 1
                  , PebbleUi.textIntWithFont UiResources.DefaultFont 36 74 model.hhmm
                  ]
              ]
          ]
  """

  @let_canvas_view_elm """
  module LetCanvasView exposing (..)

  type alias Model =
      { hhmm : Int, screenW : Int, screenH : Int }

  type Msg
      = Tick

  init _ =
      ( { hhmm = 1234, screenW = 144, screenH = 168 }, Cmd.none )

  view model =
      let
          cardW =
              (model.screenW * 7) // 10

          cardX =
              (model.screenW - cardW) // 2
      in
      PebbleUi.windowStack
          [ PebbleUi.window 1
              [ PebbleUi.canvasLayer 1
                  [ PebbleUi.clear 0
                  , PebbleUi.roundRect cardX 56 cardW 56 8 1
                  , PebbleUi.textIntWithFont UiResources.DefaultFont 36 74 model.hhmm
                  ]
              ]
          ]
  """

  @cmd_calls_elm """
  module CmdCalls exposing (..)

  import Pebble.Cmd as PebbleCmd

  type Msg
      = Tick
      | CurrentTime String

  init _ =
      ( {}, Cmd.none )

  update msg model =
      case msg of
          Tick ->
              ( model, PebbleCmd.getCurrentTimeString CurrentTime )

          CurrentTime value ->
              ( model, Cmd.none )
  """

  @http_cmd_calls_elm """
  module CmdCallsHttp exposing (..)

  import Companion.Http as Http
  import Json.Decode as Decode

  type Msg
      = Tick
      | WeatherReceived (Result Http.Error Float)

  update msg model =
      case msg of
          Tick ->
              let
                  weatherRequest =
                      Http.get
                          { url = "https://example.com/weather"
                          , expect =
                              Http.expectJson
                                  (Decode.field "value" Decode.float)
                                  WeatherReceived
                          }
              in
              ( model, Http.send httpRequest weatherRequest )

          WeatherReceived value ->
              ( model, Cmd.none )
  """

  test "analyze_source extracts init model, Msg tags, and view outline" do
    assert {:ok, %{"elm_introspect" => ei}} = ElmIntrospect.analyze_source(@mini_elm, "Snap.elm")

    assert ei["module"] == "Snap"
    assert is_integer(ei["source_byte_size"]) and ei["source_byte_size"] > 0
    assert is_integer(ei["source_line_count"]) and ei["source_line_count"] > 0
    assert ei["module_exposing"] == ".."
    assert "Inc" in ei["msg_constructors"]
    assert "Dec" in ei["msg_constructors"]
    assert ei["init_cmd_ops"] == ["Cmd.none"]

    assert %{"count" => 0, "note" => %{"$ctor" => "Nothing", "$args" => []}} = ei["init_model"]

    vt = ei["view_tree"]
    assert vt["type"] == "windowStack"
    assert [_ | _] = vt["children"]
    assert ei["view_case_branches"] == []
    assert ei["view_case_subject"] == nil
    assert ei["ports"] == []
    assert ei["port_module"] == false
    assert ei["import_entries"] == []
    assert ei["imported_modules"] == []
    assert ei["type_aliases"] == []
    assert "Msg" in ei["unions"]
    assert "init" in ei["functions"]
    assert "view" in ei["functions"]
  end

  test "analyze_source strips utf-8 bom for source-derived header scans" do
    src = <<0xEF, 0xBB, 0xBF>> <> @mini_elm

    assert {:ok, %{"elm_introspect" => ei}} = ElmIntrospect.analyze_source(src, "Snap.elm")

    assert ei["module"] == "Snap"
    assert ei["module_exposing"] == ".."
    assert is_integer(ei["source_byte_size"]) and ei["source_byte_size"] == byte_size(src)
  end

  test "analyze_source view tree keeps literal and field_access labels for draw args" do
    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(@numeric_view_elm, "NumericView.elm")

    labels = tree_labels(ei["view_tree"])

    assert "36" in labels
    assert "74" in labels
    assert "model.hhmm" in labels
  end

  test "analyze_source keeps drawable nodes for let-based canvas view" do
    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(@let_canvas_view_elm, "LetCanvasView.elm")

    types = tree_types(ei["view_tree"])
    assert "clear" in types
    assert "roundRect" in types
    assert "textIntWithFont" in types
  end

  test "analyze_source preserves shorthand arithmetic operands in view tree" do
    source = """
    module ShorthandArithmeticView exposing (..)

    view model =
        let
            x =
                model.screenW // 2

            y =
                model.screenH // 4

            w =
                model.screenW + model.screenH
        in
        PebbleUi.fillRect { x = x + 2, y = y + 2, w = w - 4, h = 4 } 1
    """

    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(source, "ShorthandArithmeticView.elm")

    nodes = collect_tree_nodes(ei["view_tree"])

    assert Enum.any?(nodes, fn node ->
             Map.get(node, "type") == "call" and Map.get(node, "label") == "__add__" and
               Enum.any?(Map.get(node, "children", []), &(Map.get(&1, "label") == "x"))
           end)

    assert Enum.any?(nodes, fn node ->
             Map.get(node, "type") == "call" and Map.get(node, "label") == "__sub__" and
               Enum.any?(Map.get(node, "children", []), &(Map.get(&1, "label") == "w"))
           end)
  end

  test "analyze_source keeps drawable nodes for watchface digital template source" do
    path = Path.expand("../../../priv/project_templates/watchface_digital/src/Main.elm", __DIR__)
    source = File.read!(path)

    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(source, "Main.elm")

    types = tree_types(ei["view_tree"])
    assert "clear" in types
    assert "roundRect" in types
    assert "textLabel" in types
  end

  test "analyze_source keeps tuple selector operand nodes for watchface analog source" do
    path = Path.expand("../../../priv/project_templates/watchface_analog/src/Main.elm", __DIR__)
    source = File.read!(path)

    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(source, "Main.elm")

    nodes = collect_tree_nodes(ei["view_tree"])

    tuple_first =
      Enum.find(nodes, fn node ->
        Map.get(node, "type") == "expr" and Map.get(node, "op") == "tuple_first_expr"
      end)

    tuple_second =
      Enum.find(nodes, fn node ->
        Map.get(node, "type") == "expr" and Map.get(node, "op") == "tuple_second_expr"
      end)

    assert is_map(tuple_first)
    assert is_map(tuple_second)

    assert [first_child] = Map.get(tuple_first, "children")
    assert [second_child] = Map.get(tuple_second, "children")
    assert is_map(first_child)
    assert is_map(second_child)
    assert Map.get(first_child, "type") != "unknown"
    assert Map.get(second_child, "type") != "unknown"
  end

  test "analyze_source preserves UI call argument names from package contracts" do
    path = Path.expand("../../../priv/project_templates/watchface_analog/src/Main.elm", __DIR__)
    source = File.read!(path)

    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(source, "Main.elm")

    line =
      ei["view_tree"]
      |> collect_tree_nodes()
      |> Enum.find(fn node -> Map.get(node, "type") == "line" end)

    assert is_map(line)
    assert line["qualified_target"] == "PebbleUi.line"
    assert line["arg_names"] == ["startPos", "endPos", "color"]
  end

  test "analyze_source keeps tuple2 operands in view tree nodes" do
    source = """
    module Main exposing (main)

    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color

    type alias Model =
        {}

    type Msg
        = Tick

    init _ =
        ( {}, Ui.cmdNone )

    update msg model =
        ( model, Ui.cmdNone )

    view _ =
        let
            pair =
                ( 1, 2 )
        in
        [ Ui.line { x = Tuple.first pair, y = Tuple.second pair } { x = 3, y = 4 } Color.black ]

    subscriptions _ =
        Ui.onTick Tick

    main =
        Ui.watchApp
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            }
    """

    assert {:ok, %{"elm_introspect" => ei}} = ElmIntrospect.analyze_source(source, "Main.elm")

    tuple2_nodes =
      collect_tree_nodes(ei["view_tree"])
      |> Enum.filter(&(Map.get(&1, "type") == "expr" and Map.get(&1, "op") == "tuple2"))

    assert tuple2_nodes != []
    assert Enum.all?(tuple2_nodes, fn node -> length(Map.get(node, "children") || []) == 2 end)
  end

  test "analyze_source extracts structured update command calls with callback constructor" do
    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(@cmd_calls_elm, "CmdCalls.elm")

    calls = ei["update_cmd_calls"]
    assert is_list(calls)

    assert Enum.any?(calls, fn row ->
             (row["name"] == "getCurrentTimeString" || row[:name] == "getCurrentTimeString") and
               (row["callback_constructor"] == "CurrentTime" ||
                  row[:callback_constructor] == "CurrentTime") and
               (row["branch_constructor"] == "Tick" || row[:branch_constructor] == "Tick")
           end)
  end

  test "analyze_source resolves callback constructor through Http.send request binding" do
    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(@http_cmd_calls_elm, "CmdCallsHttp.elm")

    calls = ei["update_cmd_calls"]
    assert is_list(calls)

    assert Enum.any?(calls, fn row ->
             (row["name"] == "send" || row[:name] == "send") and
               (row["callback_constructor"] == "WeatherReceived" ||
                  row[:callback_constructor] == "WeatherReceived")
           end)
  end

  @with_block_comment """
  {- file overview: DocMod
     (not a declaration)
  -}
  module DocMod exposing (..)

  import Html

  type Msg
      = X

  init _ =
      ( {}, Cmd.none )

  update _ m =
      m

  view _ =
      Html.text ""
  """

  test "analyze_source strips block comments before source-derived scans" do
    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(@with_block_comment, "DocMod.elm")

    assert ei["module"] == "DocMod"
    assert ei["module_exposing"] == ".."
    assert ei["port_module"] == false
    assert Enum.map(ei["import_entries"], & &1["module"]) == ["Html"]
  end

  @with_eol_comments """
  module Eol exposing (..) -- file header

  import Html -- UI
  import Json.Encode as JE exposing (object)  -- encoders

  type Msg
      = X

  port toJs : String -> Cmd msg -- outbound

  init _ =
      ( {}, Cmd.none )

  update _ m =
      m

  view _ =
      Html.text ""
  """

  test "analyze_source strips trailing line comments on source-derived header lines" do
    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(@with_eol_comments, "Eol.elm")

    assert ei["module"] == "Eol"
    assert ei["module_exposing"] == ".."
    assert ei["port_module"] == false
    assert Enum.map(ei["import_entries"], & &1["module"]) == ["Html", "Json.Encode"]

    assert Enum.at(ei["import_entries"], 1)["as"] == "JE"
    assert Enum.at(ei["import_entries"], 1)["exposing"] == ["object"]

    assert ei["ports"] == ["toJs"]
  end

  @with_imports """
  module Imp exposing (..)

  import Html
  import Platform

  type Msg
      = X

  init _ =
      ( {}, Cmd.none )

  update _ m =
      m

  view _ =
      X.y []
  """

  test "analyze_source lists explicit imported_modules without implicit core" do
    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(@with_imports, "Imp.elm")

    assert Enum.map(ei["import_entries"], & &1["module"]) == ["Html", "Platform"]
    assert "Html" in ei["imported_modules"]
    assert "Platform" in ei["imported_modules"]
    refute "Basics" in ei["imported_modules"]
    refute "List" in ei["imported_modules"]
    assert "Msg" in ei["unions"]
    assert "init" in ei["functions"]
    assert "update" in ei["functions"]
    assert "view" in ei["functions"]
    assert ei["module_exposing"] == ".."
  end

  @import_flexible_ws """
  module Spc exposing (..)

  import  Html
  import\tPlatform

  type Msg
      = X

  init _ =
      ( {}, Cmd.none )

  update _ m =
      m

  view _ =
      Html.text ""
  """

  test "analyze_source accepts import after flexible whitespace" do
    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(@import_flexible_ws, "Spc.elm")

    assert Enum.map(ei["import_entries"], & &1["module"]) == ["Html", "Platform"]
  end

  @import_exposing_flex """
  module ExpWs exposing (..)

  import Html  exposing  ( div , text )
  import Json.Decode as Decode exposing(..)

  type Msg
      = X

  init _ =
      ( {}, Cmd.none )

  update _ m =
      m

  view _ =
      div [] [ text "x" ]
  """

  test "analyze_source accepts flexible whitespace in import exposing clause" do
    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(@import_exposing_flex, "ExpWs.elm")

    [a, b] = ei["import_entries"]
    assert a["module"] == "Html"
    assert a["exposing"] == ["div", "text"]
    assert b["module"] == "Json.Decode"
    assert b["as"] == "Decode"
    assert b["exposing"] == ".."
  end

  @import_as_flex """
  module AsFlex exposing (..)

  import Json.Decode  as  Decode exposing (string)

  type Msg
      = X

  init _ =
      ( {}, Cmd.none )

  update _ m =
      m

  view _ =
      Html.text ""
  """

  test "analyze_source accepts flexible whitespace around import as" do
    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(@import_as_flex, "AsFlex.elm")

    [e] = ei["import_entries"]
    assert e["module"] == "Json.Decode"
    assert e["as"] == "Decode"
    assert e["exposing"] == ["string"]
  end

  @import_syn """
  module ISyn exposing (..)

  import Html exposing (div, text)
  import Json.Decode as Decode exposing (..)

  type Msg
      = X

  init _ =
      ( {}, Cmd.none )

  update _ m =
      m

  view _ =
      div [] [ text "ok" ]
  """

  test "analyze_source captures import as and exposing clauses from source" do
    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(@import_syn, "ISyn.elm")

    [h, j] = ei["import_entries"]
    assert h["module"] == "Html"
    assert h["as"] == nil
    assert h["exposing"] == ["div", "text"]
    assert j["module"] == "Json.Decode"
    assert j["as"] == "Decode"
    assert j["exposing"] == ".."
  end

  @import_multiline """
  module IMl exposing (..)

  import Html exposing ( div
      , text
      )

  import Json.Decode as D exposing ( Decoder
      , string
      )

  type Msg
      = X

  init _ =
      ( {}, Cmd.none )

  update _ m =
      m

  view _ =
      div [] [ text "ok" ]
  """

  test "analyze_source joins multiline import exposing lists" do
    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(@import_multiline, "IMl.elm")

    [a, b] = ei["import_entries"]
    assert a["module"] == "Html"
    assert a["exposing"] == ["div", "text"]
    assert b["module"] == "Json.Decode"
    assert b["as"] == "D"
    assert b["exposing"] == ["Decoder", "string"]
  end

  @import_nested_paren """
  module INest exposing (..)

  import Parser exposing (Parser(..), Step(..), loop)

  type Msg
      = X

  init _ =
      ( {}, Cmd.none )

  update _ m =
      m

  view _ =
      Html.text ""
  """

  test "analyze_source parses import exposing with nested (..) in one line" do
    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(@import_nested_paren, "INest.elm")

    [e] = ei["import_entries"]
    assert e["module"] == "Parser"
    assert e["exposing"] == ["Parser(..)", "Step(..)", "loop"]
  end

  @import_exposing_commas_in_types """
  module ITy exposing (..)

  import Html exposing (div, Maybe ( Int , Bool ))

  type Msg
      = X

  init _ =
      ( {}, Cmd.none )

  update _ m =
      m

  view _ =
      div [] []
  """

  test "analyze_source splits import exposing on commas not inside type parens" do
    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(@import_exposing_commas_in_types, "ITy.elm")

    [e] = ei["import_entries"]
    assert e["module"] == "Html"
    assert e["exposing"] == ["div", "Maybe(Int,Bool)"]
  end

  @module_exposing_commas_in_types """
  module MTy exposing (map, Result ( String , Int ))

  type Msg
      = X

  init _ =
      ( {}, Cmd.none )

  update _ m =
      m

  view _ =
      Html.text ""
  """

  test "analyze_source splits module exposing on commas not inside type parens" do
    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(@module_exposing_commas_in_types, "MTy.elm")

    assert ei["module_exposing"] == ["map", "Result(String,Int)"]
  end

  @with_exposing_pick """
  module Pick exposing (init, view, Model)

  type Msg
      = X

  init _ =
      ( {}, Cmd.none )

  update _ m =
      m

  view _ =
      X.y []
  """

  test "analyze_source parses explicit module exposing list from header" do
    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(@with_exposing_pick, "Pick.elm")

    assert ei["module_exposing"] == ["init", "view", "Model"]
  end

  @multiline_exposing """
  module Multi exposing (
      init
    , view
    , Model
    )

  type Msg
      = X

  init _ =
      ( {}, Cmd.none )

  update _ m =
      m

  view _ =
      X.y []
  """

  test "analyze_source parses module exposing list split across lines" do
    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(@multiline_exposing, "Multi.elm")

    assert ei["module"] == "Multi"
    assert ei["module_exposing"] == ["init", "view", "Model"]
  end

  @exposing_with_subparens """
  module SubPar exposing (init, Msg(..), Model)

  type Msg
      = X

  init _ =
      ( {}, Cmd.none )

  update _ m =
      m

  view _ =
      X.y []
  """

  test "analyze_source parses exposing list with constructor (..) inside parentheses" do
    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(@exposing_with_subparens, "SubPar.elm")

    assert ei["module_exposing"] == ["init", "Msg(..)", "Model"]
  end

  @with_ports """
  port module Portm exposing (..)

  port toJs : String -> Cmd msg

  port fromJs : (String -> msg) -> Sub msg

  init _ =
      ( {}, Cmd.none )

  update _ m =
      m

  view _ =
      X.x []
  """

  test "analyze_source extracts top-level port names from source" do
    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(@with_ports, "Portm.elm")

    assert ei["ports"] == ["toJs", "fromJs"]
    assert ei["port_module"] == true
  end

  @with_ports_multiline """
  port module PortML exposing (..)

  port oneLine : String -> Cmd msg

  port splitPort
      : Int -> Cmd msg

  port splitSub
      : (String -> msg) -> Sub msg

  init _ =
      ( {}, Cmd.none )

  update _ m =
      m

  view _ =
      X.x []
  """

  test "analyze_source extracts port names when the signature continues on the next line" do
    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(@with_ports_multiline, "PortML.elm")

    assert ei["ports"] == ["oneLine", "splitPort", "splitSub"]
  end

  @view_case_model """
  module ViewMdl exposing (..)

  type Model
      = Home
      | Settings

  init _ =
      ( Home, Cmd.none )

  update _ m =
      m

  view model =
      case model of
          Home ->
              X.a []
          Settings ->
              X.b []
  """

  test "analyze_source extracts view_case_branches for case on model" do
    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(@view_case_model, "ViewMdl.elm")

    assert ei["view_case_subject"] == "model"
    assert "Home" in ei["view_case_branches"]
    assert "Settings" in ei["view_case_branches"]
  end

  @view_case_page """
  module ViewPg exposing (..)

  type Page
      = Home
      | Settings

  type alias Model =
      { page : Page }

  init _ =
      ( { page = Home }, Cmd.none )

  update _ m =
      m

  view model =
      case model.page of
          Home ->
              X.a []
          Settings ->
              X.b []
  """

  test "analyze_source extracts view_case_branches for case on model field access" do
    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(@view_case_page, "ViewPg.elm")

    assert ei["view_case_subject"] == "model.page"
    assert "Home" in ei["view_case_branches"]
    assert "Settings" in ei["view_case_branches"]
  end

  @update_case_field """
  module UpdPg exposing (..)

  type Page
      = Pa
      | Pb

  type alias Model =
      { page : Page }

  init _ =
      ( { page = Pa }, Cmd.none )

  update msg model =
      case model.page of
          Pa ->
              model
          Pb ->
              model

  view _ =
      X.x []
  """

  test "analyze_source extracts update_case_branches for case on model field access" do
    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(@update_case_field, "UpdPg.elm")

    assert ei["update_case_subject"] == "model.page"
    assert "Pa" in ei["update_case_branches"]
    assert "Pb" in ei["update_case_branches"]
  end

  @with_update """
  module Upd exposing (..)

  type Msg
      = Inc
      | Dec

  update msg model =
      case msg of
          Inc ->
              model
          Dec ->
              model

  init _ =
      ( {}, Cmd.none )

  view _ =
      X.y []
  """

  test "analyze_source extracts update_case_branches for top-level case msg" do
    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(@with_update, "Upd.elm")

    assert "Inc" in ei["update_case_branches"]
    assert "Dec" in ei["update_case_branches"]
    assert ei["update_case_subject"] == "msg"
    assert ei["update_params"] == ["msg", "model"]
    assert ei["init_params"] == ["_"]
    assert ei["view_params"] == ["_"]
    assert ei["update_cmd_ops"] == []
  end

  @update_case_with_tuples """
  module UpdCaseCmd exposing (..)

  type Msg
      = Inc
      | Dec

  update msg model =
      case msg of
          Inc ->
              ( model, Cmd.none )
          Dec ->
              ( model, Cmd.none )

  init _ =
      ( {}, Cmd.none )

  view _ =
      X.y []
  """

  test "analyze_source extracts update_cmd_ops from case branches that return model,cmd tuples" do
    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(@update_case_with_tuples, "UpdCaseCmd.elm")

    assert ei["update_cmd_ops"] == ["Cmd.none", "Cmd.none"]
    assert "Inc" in ei["update_case_branches"]
  end

  @update_case_mixed_branch """
  module UpdMix exposing (..)

  type Msg
      = Inc
      | Dec

  update msg model =
      case msg of
          Inc ->
              ( model, Cmd.none )
          Dec ->
              model

  init _ =
      ( {}, Cmd.none )

  view _ =
      X.y []
  """

  test "analyze_source collects update_cmd_ops only from case branches with tuples" do
    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(@update_case_mixed_branch, "UpdMix.elm")

    assert ei["update_cmd_ops"] == ["Cmd.none"]
  end

  @update_case_disallowed_subject """
  module UpdBadSubject exposing (..)

  type Msg
      = A

  update msg model =
      case mystery of
          A ->
              ( model, Cmd.none )

  init _ =
      ( {}, Cmd.none )

  view _ =
      X.y []
  """

  test "analyze_source does not extract update_cmd_ops from case when subject is not a recognized update scrutinee" do
    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(@update_case_disallowed_subject, "UpdBadSubject.elm")

    assert ei["update_case_branches"] == []
    assert ei["update_cmd_ops"] == []
  end

  @update_top_tuple """
  module UpTup exposing (..)

  type Msg
      = X

  update _ m =
      ( m, Cmd.none )

  init _ =
      ( {}, Cmd.none )

  view _ =
      X.y []
  """

  test "analyze_source extracts update_cmd_ops when update is a top-level model,cmd tuple" do
    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(@update_top_tuple, "UpTup.elm")

    assert ei["update_cmd_ops"] == ["Cmd.none"]
  end

  @with_update_m """
  module UpdM exposing (..)

  type Msg
      = Inc
      | Dec

  update m model =
      case m of
          Inc ->
              model
          Dec ->
              model

  init _ =
      ( {}, Cmd.none )

  view _ =
      X.y []
  """

  test "analyze_source extracts update_case_branches when case subject is first update param" do
    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(@with_update_m, "UpdM.elm")

    assert "Inc" in ei["update_case_branches"]
    assert "Dec" in ei["update_case_branches"]
    assert ei["update_case_subject"] == "m"
    assert ei["update_params"] == ["m", "model"]
  end

  @with_subs """
  module Subm exposing (..)

  type Msg
      = T
      | U

  subscriptions _ =
      Evts.batch [ Evts.onTick T, Evts.onTap U ]

  init _ =
      ( {}, Cmd.none )

  view _ =
      X.y []
  """

  test "analyze_source extracts subscription_ops from batch list" do
    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(@with_subs, "Subm.elm")

    ops = ei["subscription_ops"]
    assert is_list(ops)
    assert Enum.any?(ops, &String.contains?(&1, "onTick"))
    assert Enum.any?(ops, &String.contains?(&1, "onTap"))

    calls = ei["subscription_calls"]

    assert Enum.any?(
             calls,
             &match?(%{"event_kind" => "on_tick", "callback_constructor" => "T"}, &1)
           )

    assert Enum.any?(
             calls,
             &match?(%{"event_kind" => "on_tap", "callback_constructor" => "U"}, &1)
           )
  end

  @subs_case """
  module SubCase exposing (..)

  type Msg
      = T
      | U

  type Page
      = Home
      | Settings

  subscriptions model =
      case model.page of
          Home ->
              Sub.none
          Settings ->
              Evts.batch [ Evts.onTick T, Evts.onTap U ]

  init _ =
      ( {}, Cmd.none )

  update _ m =
      m

  view _ =
      X.y []
  """

  test "analyze_source merges subscription_ops from case branches when subject matches subscriptions params" do
    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(@subs_case, "SubCase.elm")

    assert ei["subscriptions_params"] == ["model"]
    ops = ei["subscription_ops"]
    assert Enum.any?(ops, &String.contains?(&1, "onTick"))
    assert Enum.any?(ops, &String.contains?(&1, "onTap"))
    assert "Home" in ei["subscriptions_case_branches"]
    assert "Settings" in ei["subscriptions_case_branches"]
    assert ei["subscriptions_case_subject"] == "model.page"
    assert "Sub.none" in ei["subscription_ops"]
  end

  @subs_case_bad """
  module SubBad exposing (..)

  type Msg = T

  subscriptions _ =
      case wat of
          X ->
              Evts.batch [ Evts.onTick T ]

  init _ =
      ( {}, Cmd.none )

  update _ m =
      m

  view _ =
      X.y []
  """

  test "analyze_source does not invent subscription_ops from unrecognized case subject" do
    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(@subs_case_bad, "SubBad.elm")

    assert ei["subscriptions_params"] == ["_"]
    assert ei["subscription_ops"] == []
  end

  @with_main_worker """
  module Wkr exposing (..)

  type Msg
      = Tick

  init _ =
      ( {}, Cmd.none )

  update _ m =
      m

  subscriptions _ =
      Sub.none

  main =
      Platform.worker
          { init = init
          , update = update
          , subscriptions = subscriptions
          }
  """

  @init_cmd_batch """
  module CmdBat exposing (..)

  type Msg
      = X

  init _ =
      ( {}, Cmd.batch [ Cmd.none, Cmd.none ] )

  view _ =
      Html.text ""
  """

  test "analyze_source extracts init_cmd_ops from Cmd.batch in init" do
    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(@init_cmd_batch, "CmdBat.elm")

    assert ei["init_cmd_ops"] == ["Cmd.none", "Cmd.none"]
  end

  @init_case_cmds """
  module InitCase exposing (..)

  type Flags
      = Public
      | Secret

  type Msg
      = X

  init flags =
      case flags of
          Public ->
              ( {}, Cmd.none )
          Secret ->
              ( {}, Cmd.batch [ Cmd.none, Cmd.none ] )

  update _ m =
      m

  view _ =
      Html.text ""
  """

  test "analyze_source extracts init_cmd_ops from case branches returning model,cmd tuples" do
    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(@init_case_cmds, "InitCase.elm")

    assert ei["init_params"] == ["flags"]
    assert ei["init_cmd_ops"] == ["Cmd.none", "Cmd.none", "Cmd.none"]
    assert "Public" in ei["init_case_branches"]
    assert "Secret" in ei["init_case_branches"]
    assert ei["init_case_subject"] == "flags"
    assert ei["init_model"] == %{}
  end

  @init_case_bad_subject """
  module InitBad exposing (..)

  type Msg
      = X

  init _ =
      case wat of
          X ->
              ( {}, Cmd.none )

  update _ m =
      m

  view _ =
      Html.text ""
  """

  test "analyze_source does not extract init_cmd_ops from case when subject is not a recognized init scrutinee" do
    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(@init_case_bad_subject, "InitBad.elm")

    assert ei["init_params"] == ["_"]
    assert ei["init_cmd_ops"] == []
  end

  test "analyze_source extracts main_program for Platform.worker-style main" do
    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(@with_main_worker, "Wkr.elm")

    mp = ei["main_program"]
    assert is_map(mp)
    assert mp["kind"] == "worker"
    assert mp["target"] == "Platform.worker"
    assert "init" in mp["fields"]
    assert "update" in mp["fields"]
    assert "subscriptions" in mp["fields"]
  end

  defp tree_labels(node) when is_map(node) do
    label =
      case Map.get(node, "label") do
        value when is_binary(value) and value != "" -> [value]
        _ -> []
      end

    children =
      case Map.get(node, "children") do
        value when is_list(value) -> value
        _ -> []
      end

    label ++ Enum.flat_map(children, &tree_labels/1)
  end

  defp tree_labels(_), do: []

  defp tree_types(node) when is_map(node) do
    type =
      case Map.get(node, "type") do
        value when is_binary(value) and value != "" -> [value]
        _ -> []
      end

    children =
      case Map.get(node, "children") do
        value when is_list(value) -> value
        _ -> []
      end

    type ++ Enum.flat_map(children, &tree_types/1)
  end

  defp tree_types(_), do: []

  defp collect_tree_nodes(node) when is_map(node) do
    children =
      case Map.get(node, "children") do
        value when is_list(value) -> value
        _ -> []
      end

    [node | Enum.flat_map(children, &collect_tree_nodes/1)]
  end

  defp collect_tree_nodes(_), do: []
end
