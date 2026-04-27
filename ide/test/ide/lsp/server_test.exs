defmodule Ide.Lsp.ServerTest do
  use Ide.DataCase, async: true

  alias Ide.Lsp.Server

  test "initializes with editor language capabilities" do
    {messages, _state} =
      Server.handle(
        Jason.encode!(%{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize", "params" => %{}}),
        Server.new("demo")
      )

    assert [%{"id" => 1, "result" => %{"capabilities" => capabilities}}] = messages
    assert capabilities["documentFormattingProvider"]
    assert capabilities["completionProvider"]
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
