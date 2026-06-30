defmodule Elmx.ElmCoreExposedApiTest do
  use ExUnit.Case, async: true

  alias Elmx.Backend.ElixirCodegen.Emit
  alias Elmx.Backend.ElixirCodegen.Emit.Qualified
  alias Elmx.Backend.UnsupportedOpError

  @api [
    {"Maybe.map3", 4},
    {"Maybe.map4", 5},
    {"Maybe.map5", 6},
    {"Result.map2", 3},
    {"Result.map3", 4},
    {"Result.map4", 5},
    {"Result.map5", 6},
    {"Task.map3", 4},
    {"Task.map4", 5},
    {"Task.map5", 6},
    {"Task.sequence", 1},
    {"Task.attempt", 2},
    {"Task.onError", 2},
    {"Task.mapError", 2}
  ]

  test "newly added elm/core qualified calls compile in elmx" do
    env =
      Emit.function_env("Main", [])
      |> Map.put(:module, "Main")
      |> Map.put(:zero_arity_fns, MapSet.new())
      |> Map.put(:function_arities, %{})
      |> Map.put(:constructor_lookup, %{})

    missing =
      Enum.filter(@api, fn {target, arity} ->
        args = dummy_args(arity)

        try do
          {_code, _env, _c} =
            Qualified.compile_qualified_call(%{op: :qualified_call, target: target, args: args}, env, 0)

          false
        rescue
          UnsupportedOpError -> true
        end
      end)

    assert missing == [],
           """
           Missing elm/core API compile support:
           #{Enum.map_join(missing, "\n", fn {t, a} -> "  #{t} @ #{a}" end)}
           """
  end

  test "List.find is not elm/core and is rejected" do
    env =
      Emit.function_env("Main", [])
      |> Map.put(:module, "Main")
      |> Map.put(:zero_arity_fns, MapSet.new())
      |> Map.put(:function_arities, %{})
      |> Map.put(:constructor_lookup, %{})

    assert_raise UnsupportedOpError, fn ->
      Qualified.compile_qualified_call(
        %{
          op: :qualified_call,
          target: "List.find",
          args: [%{op: :var, name: "f"}, %{op: :list_literal, items: []}]
        },
        env,
        0
      )
    end
  end

  defp dummy_args(arity) do
    Enum.map(1..arity, fn i ->
      case rem(i, 4) do
        0 -> %{op: :int_literal, value: 1}
        1 -> %{op: :string_literal, value: "x"}
        2 -> %{op: :var, name: "f"}
        _ -> %{op: :list_literal, items: []}
      end
    end)
  end
end
