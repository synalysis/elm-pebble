defmodule Ide.Formatter.EditEngineTest do
  use ExUnit.Case, async: true

  alias Ide.Formatter
  alias Ide.Formatter.EditEngine

  test "tab inserts the next indentation stop" do
    source = "value =\n1\n"
    start = String.length("value =\n")
    result = EditEngine.compute_tab_edit(source, start, start, false)

    assert result.next_content == "value =\n    1\n"
    assert result.cursor_start == start + 4
    assert result.cursor_end == result.cursor_start
  end

  test "shift-tab removes indentation from selected block" do
    source = "value =\n    one\n    two\n"
    start = String.length("value =\n")
    end_offset = String.length("value =\n    one\n    two")
    result = EditEngine.compute_tab_edit(source, start, end_offset, true)

    assert result.next_content == "value =\none\ntwo\n"
    assert result.cursor_end > result.cursor_start
  end

  test "enter aligns with record opening brace before comma" do
    source = "    { value : Int, temperature : Maybe Int }"
    cursor = String.length("    { value : Int")
    result = EditEngine.compute_enter_edit(source, cursor, cursor)

    assert result.next_content == "    { value : Int\n    , temperature : Maybe Int }"
  end

  test "enter indents one level after assignment operator" do
    source = "value ="
    cursor = String.length(source)
    result = EditEngine.compute_enter_edit(source, cursor, cursor)

    assert result.next_content == "value =\n    "
  end

  test "enter indents one level after union type declaration head" do
    source = "type MyType"
    cursor = String.length(source)
    result = EditEngine.compute_enter_edit(source, cursor, cursor)

    assert result.next_content == "type MyType\n    "
  end

  test "enter on equals in compact union type moves equals to indented next line" do
    source = "type MyType= FirstType"
    cursor = String.length("type MyType")
    result = EditEngine.compute_enter_edit(source, cursor, cursor)

    assert result.next_content == "type MyType\n    = FirstType"
  end

  test "enter just after equals in compact union type still indents equals line" do
    source = "type MyType= FirstType"
    cursor = String.length("type MyType=")
    result = EditEngine.compute_enter_edit(source, cursor, cursor)

    assert result.next_content == "type MyType\n    = FirstType"
  end

  test "enter normalizes existing misaligned union pipe indentation" do
    source = """
    type MyType
        = FirstType
         | SecondType
    """

    cursor = String.length(String.trim_trailing(source))
    result = EditEngine.compute_enter_edit(source, cursor, cursor)

    assert String.contains?(result.next_content, "    = FirstType\n    | SecondType")
  end

  test "formatter tab edit returns text patch payload" do
    source = "value =\n1\n"
    start = String.length("value =\n")
    patch = Formatter.compute_tab_edit(source, start, start, false)

    assert is_integer(patch.replace_from)
    assert is_integer(patch.replace_to)
    assert is_binary(patch.inserted_text)
    assert apply_patch(source, patch) == "value =\n    1\n"
  end

  test "enter patch remains stable after formatting" do
    source = """
    module Main exposing (model)

    model = { value = 1, temperature = 2 }
    """

    cursor = String.length("module Main exposing (model)\n\nmodel = { value = 1")
    patch = Formatter.compute_enter_edit(source, cursor, cursor)
    patched = apply_patch(source, patch)

    assert {:ok, formatted_once} = Formatter.format(patched)
    assert {:ok, formatted_twice} = Formatter.format(formatted_once.formatted_source)
    assert formatted_once.formatted_source == formatted_twice.formatted_source
  end

  defp apply_patch(content, patch) do
    String.slice(content, 0, patch.replace_from) <>
      patch.inserted_text <>
      String.slice(content, patch.replace_to, String.length(content) - patch.replace_to)
  end
end
