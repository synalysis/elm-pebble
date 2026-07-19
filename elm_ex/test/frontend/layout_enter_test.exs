defmodule ElmEx.Frontend.LayoutEnterTest do
  use ExUnit.Case, async: true

  alias ElmEx.Frontend.LayoutEnter

  test "enter after let indents one block level" do
    source = "let"
    offset = String.length(source)
    assert LayoutEnter.indent_string(source, offset) == "    "
  end

  test "enter after binding head indents rhs" do
    source = "    counter ="
    offset = String.length(source)
    assert LayoutEnter.indent_string(source, offset) == "        "
  end

  test "enter after completed binding stays at block indent" do
    source = "    a = 1"
    offset = String.length(source)
    assert LayoutEnter.indent_string(source, offset) == "    "
  end

  test "enter after case of indents first arm column" do
    source = "case n of"
    offset = String.length(source)
    assert LayoutEnter.indent_string(source, offset) == "    "
  end

  test "enter after case arm arrow indents body" do
    source = "    Zero ->"
    offset = String.length(source)
    assert LayoutEnter.indent_string(source, offset) == "        "
  end

  test "enter after if then indents body" do
    source = "if cond then"
    offset = String.length(source)
    assert LayoutEnter.indent_string(source, offset) == "    "
  end

  test "enter inside multiline let preserves sibling binding indent" do
    source = """
    let
        a = 1
    """

    offset = String.length(source)
    assert LayoutEnter.indent_string(source, offset) == "    "
  end

  test "tab on blank line after let snaps to block indent" do
    source = "let\n"
    offset = String.length(source)
    assert LayoutEnter.tab_insert_string(source, offset) == "    "
  end

  test "tab mid-line pads to next indent stop" do
    source = "ab"
    offset = 1
    assert LayoutEnter.tab_insert_string(source, offset) == "   "
  end
end
