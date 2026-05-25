defmodule ElmEx.ImportEntryTypesTest do
  use ExUnit.Case, async: true

  alias ElmEx.Frontend.GeneratedParser
  alias ElmEx.Frontend.Module

  test "parse_source produces typed import_entries" do
    source = """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Ui exposing (..)

    main = 0
    """

    assert {:ok, %Module{import_entries: entries}} = GeneratedParser.parse_source("Main.elm", source)
    assert length(entries) >= 2

    assert %{"module" => "Json.Decode", "as" => "Decode"} =
             Enum.find(entries, &(&1["module"] == "Json.Decode"))
  end
end
