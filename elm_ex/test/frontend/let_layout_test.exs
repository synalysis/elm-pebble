defmodule ElmEx.Frontend.LetLayoutTest do
  use ExUnit.Case, async: true

  alias ElmEx.Frontend.GeneratedExpressionParser
  alias ElmEx.Frontend.GeneratedParser
  alias ElmEx.Frontend.LetLayout

  test "validate rejects let and in on the same line" do
    assert {:error, {:inline_let_in, 1}} =
             LetLayout.validate("let counter = n + 1 in counter + 2")
  end

  test "validate accepts multiline let/in layout" do
    source = """
    let
        counter =
            n + 1
    in
    counter + 2
    """

    assert :ok = LetLayout.validate(source)
    assert {:ok, expr} = GeneratedExpressionParser.parse(source)
    assert expr.op == :let_in
  end

  test "validate accepts first binding on let line when in is on its own line" do
    source = """
    let counter = n + 1
    in
    counter + 2
    """

    assert :ok = LetLayout.validate(source)
    assert {:ok, _} = GeneratedExpressionParser.parse(source)
  end

  test "parses nested let in case branch after normalization" do
    source = """
    let
        batteryOps =
            case model.batteryLevel of
                Nothing ->
                    []

                Just batteryLevel ->
                    let
                        batteryColor =
                            if batteryLevel <= 20 then
                                PebbleColor.red

                            else if batteryLevel <= 40 then
                                PebbleColor.chromeYellow

                            else
                                PebbleColor.green
                    in
                    []
    in
    []
        |> PebbleUi.toUiNode
    """

    assert {:ok, %{op: :let_in}} = GeneratedExpressionParser.parse(source)
  end

  test "GeneratedExpressionParser normalizes inline let/in before parsing" do
    assert {:ok, %{op: :let_in}} =
             GeneratedExpressionParser.parse("let base = helper n in base + 1")
  end

  test "starter watch template Main.elm parses through generated frontend" do
    path =
      Path.expand(
        "../../ide/priv/project_templates/starter_watch/src/Main.elm",
        __DIR__
      )

    if File.exists?(path) do
      assert {:ok, module} = GeneratedParser.parse_file(path)
      assert module.name == "Main"
      assert Enum.any?(module.declarations, &(&1.name == "handleAppMsg"))
    else
      assert true
    end
  end
end
