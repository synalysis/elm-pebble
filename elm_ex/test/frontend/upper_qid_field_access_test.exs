defmodule ElmEx.Frontend.UpperQidFieldAccessTest do
  use ExUnit.Case, async: true

  alias ElmEx.Frontend.GeneratedExpressionParser

  test "module.value.field becomes qualified_ref then nested field_access" do
    assert {:ok,
            %{
              op: :field_access,
              field: "onPageChange",
              arg: %{op: :qualified_ref, target: "Shared.template"}
            }} = GeneratedExpressionParser.parse("Shared.template.onPageChange")
  end

  test "module.value stays a qualified_ref" do
    assert {:ok, %{op: :qualified_ref, target: "Shared.template"}} =
             GeneratedExpressionParser.parse("Shared.template")
  end

  test "all-uppercase QIDs stay constructor_ref" do
    assert {:ok, %{op: :constructor_ref, target: "Foo.Bar.Baz"}} =
             GeneratedExpressionParser.parse("Foo.Bar.Baz")
  end

  test "module.value with one lowercase segment is qualified_ref" do
    assert {:ok, %{op: :qualified_ref, target: "Foo.bar"}} =
             GeneratedExpressionParser.parse("Foo.bar")
  end
end
