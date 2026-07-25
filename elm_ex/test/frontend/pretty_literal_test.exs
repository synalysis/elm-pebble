defmodule ElmEx.Frontend.Pretty.LiteralTest do
  use ExUnit.Case, async: true

  alias ElmEx.Frontend.Pretty.Literal

  test "formats control characters with unicode escapes" do
    assert Literal.string_literal(<<0, 1, 31>>) ==
             "\"\\u{0000}\\u{0001}\\u{001F}\""

    assert Literal.string_literal("\\x00\\x01\\x1F") ==
             "\"\\u{0000}\\u{0001}\\u{001F}\""
  end

  test "formats non-bmp characters with unicode escapes" do
    assert Literal.char_literal(0x06DD) == "'\\u{06DD}'"
    assert Literal.char_literal(0x110BD) == "'\\u{110BD}'"
  end

  test "formats carriage return with unicode escape in control strings" do
    assert Literal.escape_string(<<13>>) == "\\u{000D}"
  end

  test "keeps named escapes for tab and newline in normal strings" do
    assert Literal.string_literal("a b") == "\"a b\""
  end
end
