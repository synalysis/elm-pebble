defmodule Elmx.SpecialValuesUiTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Pebble.SpecialValues

  test "Pebble.Ui.group and context rewrite to runtime calls" do
    ctx = %{op: :list_literal, items: []}
    ops = %{op: :list_literal, items: [%{op: :int_literal, value: 1}]}

    assert {:ok, %{op: :runtime_call, function: "elmx_ui_context", args: [^ctx, ^ops]}} =
             SpecialValues.rewrite("Pebble.Ui.context", [ctx, ops])

    assert {:ok, %{op: :runtime_call, function: "elmx_ui_group", args: [_]}} =
             SpecialValues.rewrite("Pebble.Ui.group", [ctx])
  end

  test "Pebble.Time weekday constructors rewrite to tag integers" do
    assert {:ok, %{op: :int_literal, value: 0}} = SpecialValues.rewrite("Pebble.Time.Monday", [])
    assert {:ok, %{op: :int_literal, value: 6}} = SpecialValues.rewrite("Pebble.Time.Sunday", [])
  end

  test "Pebble.Ui.Color.indexed and toInt pass through the color expression" do
    color = %{op: :int_literal, value: 42}

    assert {:ok, ^color} = SpecialValues.rewrite("Pebble.Ui.Color.indexed", [color])
    assert {:ok, ^color} = SpecialValues.rewrite("Pebble.Ui.Color.toInt", [color])
  end

  test "Pebble.Ui Pascal-case text option helpers match camelCase targets" do
    options = %{op: :list_literal, items: []}

    assert {:ok, %{op: :runtime_call, function: "elmx_ui_align_center"}} =
             SpecialValues.rewrite("Pebble.Ui.AlignCenter", [options])

    assert {:ok, %{op: :runtime_call, function: "elmx_ui_word_wrap"}} =
             SpecialValues.rewrite("Pebble.Ui.WordWrap", [options])
  end
end
