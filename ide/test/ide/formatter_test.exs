defmodule Ide.FormatterTest do
  use ExUnit.Case, async: true

  alias Ide.Formatter
  alias Ide.Formatter.Semantics.SpacingRules

  test "uses pretty backend" do
    source = "module Main exposing (main)\n\nmain = 1\n"

    assert {:ok, result} = Formatter.format(source)
    assert result.formatter == "pretty-v1"
    assert result.details.backend == :pretty
  end

  test "formats trailing spaces and ensures terminal newline" do
    source = "module Main exposing (main)\n\nmain = 1   "

    assert {:ok, result} = Formatter.format(source)
    assert result.changed?
    assert String.ends_with?(result.formatted_source, "\n")
    refute String.contains?(result.formatted_source, "   \n")
  end

  test "accepts recoverable invalid tokens in expressions" do
    source = """
    module Main exposing (main)

    value = @
    """

    assert {:ok, result} = Formatter.format(source)
    assert String.contains?(result.formatted_source, "value =")
  end

  test "normalizes type alias head spacing" do
    source = """
    module Main exposing (Model)

    type alias  Model  =
        { value : Int
        , temperature : Maybe Int
        }
    """

    assert {:ok, result} = Formatter.format(source)
    assert String.contains?(result.formatted_source, "type alias Model =")
    assert String.contains?(result.formatted_source, ", temperature : Maybe Int")
  end

  test "formats multiline record type aliases with leading commas" do
    source = """
    module Main exposing (Model)

    type alias Model =
        { now : Maybe Int
        , screenW : Int
        , screenH : Int
        }
    """

    assert {:ok, result} = Formatter.format(source)

    assert String.contains?(result.formatted_source, ", screenW : Int")
    assert String.contains?(result.formatted_source, ", screenH : Int")
    refute String.contains?(result.formatted_source, "Int, screenW")
  end

  test "restores spacing between top-level functions" do
    source = """
    module Main exposing (a, b)

    a =
        1
    b =
        2
    """

    assert {:ok, result} = Formatter.format(source)
    assert String.contains?(result.formatted_source, "a =\n    1\n\n\nb =")
  end

  test "formats union declarations" do
    source = """
    module Main exposing (Msg)

    type Msg
        = Increment  Int
        | Decrement
    """

    assert {:ok, result} = Formatter.format(source)
    assert String.contains?(result.formatted_source, "= Increment Int")
    assert String.contains?(result.formatted_source, "| Decrement")
  end

  test "preserves doc comments on declarations" do
    source = """
    module Main exposing (value)

    {-| A value
    -}
    value : Int
    value =
        1
    """

    assert {:ok, result} = Formatter.format(source)
    assert String.contains?(result.formatted_source, "{-| A value")
    assert String.contains?(result.formatted_source, "value : Int")
  end

  test "spacing rules normalize comma spacing directly" do
    assert SpacingRules.normalize_comma_spacing("a , b") == "a, b"
  end

  test "is idempotent for representative fixtures" do
    samples = [
      """
      module Main exposing (main)

      type alias Model =
          { value : Int
          , temperature : Maybe Int
          }

      main =
          1
      """,
      """
      module Main exposing (value)

      value list =
          case list of
              [] ->
                  0

              first :: rest ->
                  first
      """
    ]

    Enum.each(samples, fn source ->
      assert {:ok, once} = Formatter.format(source)
      assert {:ok, twice} = Formatter.format(once.formatted_source)
      assert twice.formatted_source == once.formatted_source
    end)
  end
end
