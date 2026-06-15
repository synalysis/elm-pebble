defmodule Ide.EditorCompletionContextTest do
  use ExUnit.Case, async: true

  alias Ide.EditorCompletionContext

  test "classifies record field access" do
    source = "update model = model.pa"
    context = EditorCompletionContext.analyze(%{source: source, offset: String.length(source)})

    assert context.kind == :record_field_access
    assert context.prefix == "pa"
  end

  test "classifies uppercase qualified access as module access" do
    source = "main = List."
    context = EditorCompletionContext.analyze(%{source: source, offset: String.length(source)})

    assert context.kind == :module_qualified_access
    assert context.qualifier == "List"
    assert context.prefix == ""
  end

  test "classifies type annotation after a colon" do
    source = "newFunction : I"
    context = EditorCompletionContext.analyze(%{source: source, offset: String.length(source)})

    assert context.kind == :type_annotation
    assert context.prefix == "I"
  end

  test "classifies normal expressions as value expressions" do
    source = "update model = ma"
    context = EditorCompletionContext.analyze(%{source: source, offset: String.length(source)})

    assert context.kind == :value_expression
    assert context.prefix == "ma"
  end
end
