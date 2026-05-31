defmodule ElmExecutor.RuntimeModelValuesTest do
  use ExUnit.Case, async: true

  alias ElmExecutor.Runtime.SemanticExecutor.RuntimeModelValues

  test "detects parser artifacts" do
    assert RuntimeModelValues.unresolved_value?(%{"$var" => "screenW"})
    assert RuntimeModelValues.unresolved_value?(%{"$opaque" => true, "op" => "if"})
    assert RuntimeModelValues.unresolved_value?(%{"call" => "Render.layoutFor", "args" => []})

    refute RuntimeModelValues.unresolved_value?(%{"boxX" => 18, "screenW" => 144})
    refute RuntimeModelValues.unresolved_value?(%{"ctor" => "Just", "args" => [88]})
  end

  test "drop_parser_artifacts removes unresolved fields" do
    model = %{
      "screenW" => 144,
      "layout" => %{"call" => "Render.layoutFor", "args" => [%{"$var" => "screenW"}]},
      "player" => %{"displayName" => "Pikachu", "x" => 24}
    }

    assert RuntimeModelValues.drop_parser_artifacts(model) == %{
             "screenW" => 144,
             "player" => %{"displayName" => "Pikachu", "x" => 24}
           }
  end
end
