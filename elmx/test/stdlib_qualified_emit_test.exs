defmodule Elmx.StdlibQualifiedEmitTest do
  use ExUnit.Case, async: true

  alias Elmx.Backend.ElixirCodegen.Emit
  alias Elmx.Backend.ElixirCodegen.Emit.Qualified, as: QualifiedEmit

  defp env do
    Emit.function_env("Main", [])
    |> Map.put(:module, "Main")
    |> Map.put(:zero_arity_fns, MapSet.new())
    |> Map.put(:function_arities, %{})
    |> Map.put(:constructor_lookup, %{})
  end

  defp emit_qualified(target, args) do
    expr = %{op: :qualified_call, target: target, args: args}
    {code, _, _} = QualifiedEmit.compile_qualified_call(expr, env(), 0)
    IO.iodata_to_binary(code)
  end

  test "collections qualified calls emit Core.Collections" do
    dict = %{op: :list_literal, items: []}
    array = %{op: :list_literal, items: [%{op: :int_literal, value: 1}]}

    assert emit_qualified("Dict.get", [%{op: :int_literal, value: 1}, dict]) =~
             "Collections.dict_get"

    assert emit_qualified("Dict.insert", [%{op: :int_literal, value: 1}, %{op: :int_literal, value: 2}, dict]) =~
             "Collections.dict_insert"

    assert emit_qualified("Set.member", [%{op: :int_literal, value: 1}, dict]) =~
             "Collections.set_member"

    assert emit_qualified("Array.get", [%{op: :int_literal, value: 0}, array]) =~
             "Collections.array_get"
  end

  test "bitwise qualified calls emit Core.Bitwise" do
    x = %{op: :int_literal, value: 5}

    assert emit_qualified("Bitwise.and", [x, x]) =~ "Core.Bitwise.and_"
    assert emit_qualified("Bitwise.shiftRightZfBy", [%{op: :int_literal, value: 1}, x]) =~
             "Core.Bitwise.shift_right_zf_by"
  end

  test "task and process qualified calls emit Core modules" do
    v = %{op: :int_literal, value: 1}

    assert emit_qualified("Task.succeed", [v]) =~ "Core.Task.succeed"
    assert emit_qualified("Process.spawn", [v]) =~ "Core.Process.spawn"
  end

  test "partial List.map and Dict.get emit unary lambdas" do
    fun = %{op: :var, name: "f"}
    key = %{op: :int_literal, value: 1}

    assert emit_qualified("List.map", [fun]) =~ "fn elmx_list ->"
    assert emit_qualified("List.map", [fun]) =~ "Core.map"

    assert emit_qualified("Dict.get", [key]) =~ "fn elmx_dict ->"
    assert emit_qualified("Dict.get", [key]) =~ "Collections.dict_get"
  end

  test "string and basics qualified calls emit expected helpers" do
    left = %{op: :string_literal, value: "a"}
    right = %{op: :string_literal, value: "b"}

    assert emit_qualified("String.append", [left, right]) =~ "Core.append"
    assert emit_qualified("Basics.modBy", [%{op: :int_literal, value: 5}, %{op: :int_literal, value: 10}]) =~
             "Integer.mod"
  end
end
