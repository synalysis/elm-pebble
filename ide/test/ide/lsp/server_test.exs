defmodule Ide.Lsp.ServerTest do
  use Ide.DataCase, async: true

  alias Ide.Lsp.Server

  test "initializes with editor language capabilities" do
    {messages, _state} =
      Server.handle(
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "initialize",
          "params" => %{}
        }),
        Server.new("demo")
      )

    assert [%{"id" => 1, "result" => %{"capabilities" => capabilities}}] = messages
    assert capabilities["documentFormattingProvider"]
    assert capabilities["completionProvider"]
    assert "." in capabilities["completionProvider"]["triggerCharacters"]
    assert ":" in capabilities["completionProvider"]["triggerCharacters"]
    assert capabilities["foldingRangeProvider"]
    assert capabilities["textDocumentSync"]["change"] == 1
  end

  test "tracks open documents and publishes diagnostics" do
    state = Server.new("demo")
    uri = "elm-pebble://demo/watch/src%2FMain.elm"

    {messages, state} =
      Server.handle(
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "method" => "textDocument/didOpen",
          "params" => %{
            "textDocument" => %{
              "uri" => uri,
              "languageId" => "elm",
              "version" => 0,
              "text" => "module Main exposing (main\n"
            }
          }
        }),
        state
      )

    assert [%{"method" => "textDocument/publishDiagnostics", "params" => params}] = messages
    assert params["uri"] == uri
    assert params["version"] == 0
    assert is_list(params["diagnostics"])

    {messages, _state} =
      Server.handle(
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => 2,
          "method" => "textDocument/completion",
          "params" => %{
            "textDocument" => %{"uri" => uri},
            "position" => %{"line" => 0, "character" => 0}
          }
        }),
        state
      )

    assert [%{"id" => 2, "result" => %{"items" => items}}] = messages
    assert Enum.any?(items, &(&1["label"] == "module"))
  end

  test "suggests alias for type al prefix" do
    state = Server.new("demo")
    uri = "elm-pebble://demo/watch/src%2FMain.elm"
    {:ok, state} = open_document(state, uri, "type al")

    {messages, _state} =
      Server.handle(
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => 5,
          "method" => "textDocument/completion",
          "params" => %{
            "textDocument" => %{"uri" => uri},
            "position" => %{"line" => 0, "character" => 7}
          }
        }),
        state
      )

    assert [%{"id" => 5, "result" => %{"items" => items}}] = messages
    assert Enum.any?(items, &(&1["label"] == "alias"))

    {messages, _state} =
      Server.handle(
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => 6,
          "method" => "textDocument/completion",
          "params" => %{
            "textDocument" => %{"uri" => uri},
            "position" => %{"line" => 0, "character" => 7}
          }
        }),
        state
      )

    assert [%{"id" => 6, "result" => %{"items" => repeat_items}}] = messages
    assert Enum.any?(repeat_items, &(&1["label"] == "alias"))
  end

  test "field accessor completion inserts field name after existing dot" do
    state = Server.new("demo")
    uri = "elm-pebble://demo/watch/src%2FMain.elm"

    text =
      [
        "type alias Model =",
        "    { pageIndex : Int }",
        "",
        "getter = .tokenOnly",
        "main model = model."
      ]
      |> Enum.join("\n")

    {:ok, state} = open_document(state, uri, text)

    {messages, _state} =
      Server.handle(
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => 7,
          "method" => "textDocument/completion",
          "params" => %{
            "textDocument" => %{"uri" => uri},
            "position" => %{"line" => 4, "character" => String.length("main model = model.")}
          }
        }),
        state
      )

    assert [%{"id" => 7, "result" => %{"items" => items}}] = messages
    labels = Enum.map(items, & &1["label"])
    assert labels == ["pageIndex"]
    refute ".tokenOnly" in labels
  end

  test "field access completion uses record alias fields instead of functions" do
    state = Server.new("demo")
    uri = "elm-pebble://demo/watch/src%2FMain.elm"

    text =
      [
        "module Main exposing (main)",
        "",
        "type alias Model =",
        "    { pageIndex : Int",
        "    , count : Int",
        "    }",
        "",
        "update model =",
        "    model."
      ]
      |> Enum.join("\n")

    {:ok, state} = open_document(state, uri, text)

    {messages, _state} =
      Server.handle(
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => 8,
          "method" => "textDocument/completion",
          "params" => %{
            "textDocument" => %{"uri" => uri},
            "position" => %{"line" => 8, "character" => String.length("    model.")}
          }
        }),
        state
      )

    assert [%{"id" => 8, "result" => %{"items" => items}}] = messages
    labels = Enum.map(items, & &1["label"])
    assert labels == ["count", "pageIndex"]
    refute "update" in labels
    refute "module" in labels
  end

  test "qualified module completion does not suggest record fields" do
    uri = "elm-pebble://demo/watch/src%2FMain.elm"

    state = %{
      Server.new("demo")
      | dependency_payloads: %{
          {"demo", "watch"} => %{
            package_doc_index: %{},
            editor_doc_packages: [
              %{
                package: "elm/core",
                docs: [
                  %{
                    "name" => "List",
                    "values" => [
                      %{"name" => "map"},
                      %{"name" => "filter"}
                    ],
                    "aliases" => [],
                    "unions" => []
                  }
                ]
              }
            ],
            direct: [],
            indirect: []
          }
        }
    }

    text =
      [
        "module Main exposing (main)",
        "",
        "type alias Model =",
        "    { pageIndex : Int }",
        "",
        "main =",
        "    List."
      ]
      |> Enum.join("\n")

    {:ok, state} = open_document(state, uri, text)

    {messages, _state} =
      Server.handle(
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => 11,
          "method" => "textDocument/completion",
          "params" => %{
            "textDocument" => %{"uri" => uri},
            "position" => %{"line" => 6, "character" => String.length("    List.")}
          }
        }),
        state
      )

    assert [%{"id" => 11, "result" => %{"items" => items}}] = messages
    labels = Enum.map(items, & &1["label"])
    assert "filter" in labels
    assert "map" in labels
    refute "pageIndex" in labels
  end

  test "import alias module completion suggests Pebble event subscriptions" do
    uri = "elm-pebble://demo/watch/src%2FMain.elm"
    {:ok, docs} = Ide.Packages.builtin_package_docs("elm-pebble/elm-watch")

    state = %{
      Server.new("demo")
      | dependency_payloads: %{
          {"demo", "watch"} => %{
            package_doc_index: %{"Pebble.Events" => "elm-pebble/elm-watch"},
            editor_doc_packages: [%{package: "elm-pebble/elm-watch", docs: docs}],
            direct: [],
            indirect: []
          }
        }
    }

    text =
      [
        "module Main exposing (main)",
        "",
        "import Pebble.Events as PebbleEvents",
        "",
        "type Msg",
        "    = HourChanged Int",
        "    | MinuteChanged Int",
        "",
        "subscriptions _ =",
        "    PebbleEvents.batch",
        "        [ PebbleEvents.onHourChange HourChanged",
        "        , PebbleEvents.onMinuteChange MinuteChanged",
        "        , PebbleEvents."
      ]
      |> Enum.join("\n")

    {:ok, state} = open_document(state, uri, text)

    {messages, _state} =
      Server.handle(
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => 13,
          "method" => "textDocument/completion",
          "params" => %{
            "textDocument" => %{"uri" => uri},
            "position" => %{"line" => 11, "character" => String.length("        , PebbleEvents.")}
          }
        }),
        state
      )

    assert [%{"id" => 13, "result" => %{"items" => items}}] = messages
    labels = Enum.map(items, & &1["label"])
    assert "onDayChange" in labels
    assert "onSecondChange" in labels
    refute "HourChanged" in labels
    refute "MinuteChanged" in labels
  end

  test "import exposing completion suggests module members after opening paren" do
    uri = "elm-pebble://demo/watch/src%2FMain.elm"
    {:ok, docs} = Ide.Packages.builtin_package_docs("elm-pebble/elm-watch")

    state = %{
      Server.new("demo")
      | dependency_payloads: %{
          {"demo", "watch"} => %{
            package_doc_index: %{"Pebble.Storage" => "elm-pebble/elm-watch"},
            editor_doc_packages: [%{package: "elm-pebble/elm-watch", docs: docs}],
            direct: [],
            indirect: []
          }
        }
    }

    text = "import Pebble.Storage as Storage exposing (\n"
    {:ok, state} = open_document(state, uri, text)

    {messages, _state} =
      Server.handle(
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => 14,
          "method" => "textDocument/completion",
          "params" => %{
            "textDocument" => %{"uri" => uri},
            "position" => %{"line" => 1, "character" => 0}
          }
        }),
        state
      )

    assert [%{"id" => 14, "result" => %{"items" => items}}] = messages
    labels = Enum.map(items, & &1["label"])
    assert ".." in labels
    assert "readInt" in labels
    assert "writeString" in labels
    refute "import" in labels
  end

  test "init context completion uses builtin package docs from dependency payload" do
    uri = "elm-pebble://demo/watch/src%2FMain.elm"
    {:ok, docs} = Ide.Packages.builtin_package_docs("elm-pebble/elm-watch")

    state = %{
      Server.new("demo")
      | dependency_payloads: %{
          {"demo", "watch"} => %{
            package_doc_index: %{"Pebble.Platform" => "elm-pebble/elm-watch"},
            editor_doc_packages: [%{package: "elm-pebble/elm-watch", docs: docs}],
            direct: [],
            indirect: []
          }
        }
    }

    text =
      [
        "module Main exposing (main)",
        "",
        "import Pebble.Platform as PebblePlatform",
        "",
        "type alias Model =",
        "    { timeString : String }",
        "",
        "init : PebblePlatform.LaunchContext -> ( Model, Cmd Msg )",
        "init context =",
        "    context."
      ]
      |> Enum.join("\n")

    {:ok, state} = open_document(state, uri, text)

    {messages, _state} =
      Server.handle(
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => 12,
          "method" => "textDocument/completion",
          "params" => %{
            "textDocument" => %{"uri" => uri},
            "position" => %{"line" => 9, "character" => String.length("    context.")}
          }
        }),
        state
      )

    assert [%{"id" => 12, "result" => %{"items" => items}}] = messages
    labels = Enum.map(items, & &1["label"])
    assert "screen" in labels
    assert "reason" in labels
    refute "timeString" in labels
  end

  test "type annotation completion suggests only type names" do
    state = Server.new("demo")
    uri = "elm-pebble://demo/watch/src%2FMain.elm"

    text =
      [
        "module Main exposing (main)",
        "",
        "type alias Model =",
        "    { count : Int }",
        "",
        "update model =",
        "    model",
        "",
        "newFunction : I"
      ]
      |> Enum.join("\n")

    {:ok, state} = open_document(state, uri, text)

    {messages, _state} =
      Server.handle(
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => 9,
          "method" => "textDocument/completion",
          "params" => %{
            "textDocument" => %{"uri" => uri},
            "position" => %{"line" => 8, "character" => String.length("newFunction : I")}
          }
        }),
        state
      )

    assert [%{"id" => 9, "result" => %{"items" => items}}] = messages
    labels = Enum.map(items, & &1["label"])
    assert "Int" in labels
    refute "update" in labels
    refute "module" in labels
    refute "import" in labels
  end

  test "value expression completion still suggests values" do
    state = Server.new("demo")
    uri = "elm-pebble://demo/watch/src%2FMain.elm"

    text =
      [
        "module Main exposing (main)",
        "",
        "mapValue model =",
        "    model",
        "",
        "main =",
        "    ma"
      ]
      |> Enum.join("\n")

    {:ok, state} = open_document(state, uri, text)

    {messages, _state} =
      Server.handle(
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => 10,
          "method" => "textDocument/completion",
          "params" => %{
            "textDocument" => %{"uri" => uri},
            "position" => %{"line" => 6, "character" => String.length("    ma")}
          }
        }),
        state
      )

    assert [%{"id" => 10, "result" => %{"items" => items}}] = messages
    assert Enum.any?(items, &(&1["label"] == "mapValue"))
  end

  test "publishes unfinished record diagnostics" do
    state = Server.new("demo")
    uri = "elm-pebble://demo/watch/src%2FMain.elm"

    {messages, _state} =
      Server.handle(
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "method" => "textDocument/didOpen",
          "params" => %{
            "textDocument" => %{
              "uri" => uri,
              "languageId" => "elm",
              "version" => 0,
              "text" => "type alias Abcd =\n    {"
            }
          }
        }),
        state
      )

    assert [%{"method" => "textDocument/publishDiagnostics", "params" => params}] = messages
    assert Enum.any?(params["diagnostics"], &String.contains?(&1["message"], "UNFINISHED RECORD"))
  end

  test "publishes uppercase record field diagnostics" do
    state = Server.new("demo")
    uri = "elm-pebble://demo/watch/src%2FMain.elm"

    {messages, _state} =
      Server.handle(
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "method" => "textDocument/didOpen",
          "params" => %{
            "textDocument" => %{
              "uri" => uri,
              "languageId" => "elm",
              "version" => 0,
              "text" => "type alias Abce =\n    { Abc : Int\n    }"
            }
          }
        }),
        state
      )

    assert [%{"method" => "textDocument/publishDiagnostics", "params" => params}] = messages

    assert Enum.any?(
             params["diagnostics"],
             &String.contains?(&1["message"], "UNEXPECTED CAPITAL LETTER")
           )
  end

  test "only publishes folding ranges longer than ten lines" do
    state = Server.new("demo")
    uri = "elm-pebble://demo/watch/src%2FMain.elm"

    short_binding = """
    w =
        model.screenW

    h =
        model.screenH
    """

    long_binding =
      [
        "view model =",
        "    group",
        "        [ text \"1\"",
        "        , text \"2\"",
        "        , text \"3\"",
        "        , text \"4\"",
        "        , text \"5\"",
        "        , text \"6\"",
        "        , text \"7\"",
        "        , text \"8\"",
        "        , text \"9\"",
        "        , text \"10\"",
        "        ]"
      ]
      |> Enum.join("\n")

    {:ok, state} = open_document(state, uri, short_binding <> "\n\n" <> long_binding)

    {messages, _state} =
      Server.handle(
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => 3,
          "method" => "textDocument/foldingRange",
          "params" => %{"textDocument" => %{"uri" => uri}}
        }),
        state
      )

    assert [%{"id" => 3, "result" => ranges}] = messages
    assert [%{"startLine" => start_line, "endLine" => end_line}] = ranges
    assert end_line - start_line > 10
    refute Enum.any?(ranges, &(&1["startLine"] in [0, 3]))
  end

  test "folding ranges exclude trailing blank lines before the next declaration" do
    state = Server.new("demo")
    uri = "elm-pebble://demo/watch/src%2FMain.elm"

    text =
      [
        "update msg model =",
        "    msg",
        "    |> one",
        "    |> two",
        "    |> three",
        "    |> four",
        "    |> five",
        "    |> six",
        "    |> seven",
        "    |> eight",
        "    |> nine",
        "    |> ten",
        "",
        "init flags model =",
        "    flags"
      ]
      |> Enum.join("\n")

    {:ok, state} = open_document(state, uri, text)

    {messages, _state} =
      Server.handle(
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => 5,
          "method" => "textDocument/foldingRange",
          "params" => %{"textDocument" => %{"uri" => uri}}
        }),
        state
      )

    assert [%{"id" => 5, "result" => ranges}] = messages

    assert Enum.any?(ranges, fn %{"startLine" => 0, "endLine" => 11} ->
             true
           end)

    refute Enum.any?(ranges, fn %{"startLine" => 0, "endLine" => end_line} ->
             end_line >= 12
           end)
  end

  test "publishes folding ranges for long let in blocks" do
    state = Server.new("demo")
    uri = "elm-pebble://demo/watch/src%2FMain.elm"

    text =
      [
        "view model =",
        "    let",
        "        w =",
        "            model.screenW",
        "        h =",
        "            model.screenH",
        "        x1 = 1",
        "        x2 = 2",
        "        x3 = 3",
        "        x4 = 4",
        "        x5 = 5",
        "        x6 = 6",
        "        x7 = 7",
        "        x8 = 8",
        "    in",
        "    w + h"
      ]
      |> Enum.join("\n")

    {:ok, state} = open_document(state, uri, text)

    {messages, _state} =
      Server.handle(
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => 4,
          "method" => "textDocument/foldingRange",
          "params" => %{"textDocument" => %{"uri" => uri}}
        }),
        state
      )

    assert [%{"id" => 4, "result" => ranges}] = messages
    assert Enum.any?(ranges, &(&1 == %{"startLine" => 1, "endLine" => 13}))
  end

  defp open_document(state, uri, text) do
    {_messages, state} =
      Server.handle(
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "method" => "textDocument/didOpen",
          "params" => %{
            "textDocument" => %{
              "uri" => uri,
              "languageId" => "elm",
              "version" => 0,
              "text" => text
            }
          }
        }),
        state
      )

    {:ok, state}
  end
end
