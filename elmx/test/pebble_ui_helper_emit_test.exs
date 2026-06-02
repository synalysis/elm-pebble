defmodule Elmx.PebbleUiHelperEmitTest do
  use ExUnit.Case, async: true

  alias Elmx.Backend.ElixirCodegen.Emit

  test "windowStack rewrites to ui window stack runtime call" do
    assert {:ok, %{op: :runtime_call, function: "elmx_ui_window_stack"}} =
             Elmx.Runtime.Pebble.SpecialValues.rewrite("Pebble.Ui.windowStack", [
               %{op: :list_literal, items: []}
             ])
  end

  test "unqualified windowStack call emits Pebble.Ui runtime helper" do
    expr = %{op: :call, name: "windowStack", args: [%{op: :list_literal, items: []}]}
    env = Emit.function_env("Pebble.Ui", []) |> Map.put(:module, "Pebble.Ui")

    {code, _, _} = Emit.compile_expr(expr, env, 0)
    assert IO.iodata_to_binary(code) =~ "Elmx.Runtime.Pebble.Ui.window_stack"
    refute IO.iodata_to_binary(code) =~ "windowStack("
  end

  test "unqualified none in Pebble.Cmd module emits cmd_none" do
    expr = %{op: :call, name: "none", args: []}
    env = Emit.function_env("Pebble.Cmd", []) |> Map.put(:module, "Pebble.Cmd")

    {code, _, _} = Emit.compile_expr(expr, env, 0)
    assert IO.iodata_to_binary(code) =~ "cmd_none"
    refute IO.iodata_to_binary(code) =~ ~r/\bnone\(/
  end

  test "let-bound multi-arg helper calls are curried" do
    label =
      %{
        op: :lambda,
        args: ["x", "y", "text_"],
        body: %{op: :int_literal, value: 0}
      }

    body =
      %{
        op: :call,
        name: "label",
        args: [
          %{op: :int_literal, value: 8},
          %{op: :int_literal, value: 36},
          %{op: :string_literal, value: "hi"}
        ]
      }

    expr = %{op: :let_in, name: "label", value_expr: label, in_expr: body}
    env = Emit.function_env("Main", ["model"])

    {code, _, _} = Emit.compile_expr(expr, env, 0)
    emitted = IO.iodata_to_binary(code)

    assert emitted =~ "fn x ->"
    assert emitted =~ "fn y ->"
    assert emitted =~ "fn text_ ->"
    assert emitted =~ "label.(8).(36).(\"hi\")"
    refute emitted =~ "label.(8, 36, \"hi\")"
  end
end
