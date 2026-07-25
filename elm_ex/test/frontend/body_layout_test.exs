defmodule ElmEx.Frontend.Pretty.BodyLayoutTest do
  use ExUnit.Case, async: true

  alias ElmEx.Frontend.Pretty.BodyLayout

  test "desugars list range literals" do
    assert BodyLayout.normalize_function_body("    [1..2]") == "    List.range 1 2"
    assert BodyLayout.normalize_function_body("    [ -1 .. 3 ]") == "    List.range -1 3"
  end

  test "normalizes hex escapes inside triple-quoted strings" do
    body = "    \"\"\"\\x00\\x0D\"\"\""

    assert BodyLayout.normalize_function_body(body) ==
             "    \"\"\"\\u{0000}\\u{000D}\"\"\""
  end

  test "drops redundant parens around qualified constructor case patterns" do
    body = """
        Maybe.Just (Maybe.Nothing) ->
            ()

        (Just _) as x ->
            ()

        ((Maybe.Nothing) as y) as x ->
            ()
    """

    normalized = BodyLayout.normalize_function_body(body)

    assert normalized =~ "Maybe.Just Maybe.Nothing ->"
    assert normalized =~ "(Just _) as x ->"
    assert normalized =~ "(Maybe.Nothing as y) as x ->"
  end
end
