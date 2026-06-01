defmodule Elmx.CaseBranchOrderTest do
  use ExUnit.Case, async: true

  alias Elmx.Backend.ElixirCodegen.Emit

  test "wildcard case branches are emitted after specific constructors" do
    env = Emit.function_env("Main", ["msg"])
    subject = %{op: :var, name: "msg"}

    branches = [
      %{pattern: %{kind: :wildcard}, expr: %{op: :int_literal, value: 0}},
      %{
        pattern: %{kind: :constructor, name: "Increment", arg_pattern: nil},
        expr: %{op: :int_literal, value: 1}
      }
    ]

    {code, _, _} =
      Emit.compile_expr(%{op: :case, subject: subject, branches: branches}, env, 0)

    source = IO.iodata_to_binary(code)
    {inc_pos, _} = :binary.match(source, ":Increment ->")
    {wild_pos, _} = :binary.match(source, "_ ->")
    assert inc_pos < wild_pos
  end
end
