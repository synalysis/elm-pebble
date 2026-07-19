defmodule ElmEx.Frontend.LayoutTest do
  use ExUnit.Case, async: true

  alias ElmEx.Frontend.Layout

  test "dedent_uniform_leading_whitespace removes shared heredoc padding" do
    source = """
         let
             a = 1
         in
             a
    """

    assert Layout.dedent_uniform_leading_whitespace(source) == """
           let
               a = 1
           in
               a
           """
  end

  test "dedent_uniform_leading_whitespace is noop when lines share no padding" do
    source = "let\n    a = 1\nin\n    a"
    assert Layout.dedent_uniform_leading_whitespace(source) == source
  end
end
