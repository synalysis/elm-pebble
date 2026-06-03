defmodule Elmx.GotSupportedCaseTest do
  use ExUnit.Case, async: true

  alias Elmx.Backend.ElixirCodegen.Emit
  test "case on msg emits GotSupported false branch matching runtime booleans" do
    env = Emit.function_env("Main", ["msg"]) |> Map.put(:module, "Main")

    branches = [
      %{
        pattern: %{
          kind: :constructor,
          name: "GotSupported",
          arg_pattern: %{kind: :constructor, name: "True", arg_pattern: nil}
        },
        expr: %{op: :int_literal, value: 1}
      },
      %{
        pattern: %{
          kind: :constructor,
          name: "GotSupported",
          arg_pattern: %{kind: :constructor, name: "False", arg_pattern: nil}
        },
        expr: %{op: :int_literal, value: 2}
      }
    ]

    {code, _, _} =
      Emit.compile_expr(
        %{op: :case, subject: %{op: :var, name: "msg"}, branches: branches},
        env,
        0
      )

    source = IO.iodata_to_binary(code)
    assert source =~ "{:GotSupported, true}"
    assert source =~ "{:GotSupported, false}"

    refute source =~ ":True"
    refute source =~ ":False"
  end

end
