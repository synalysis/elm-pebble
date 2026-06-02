defmodule Elmx.ElmCoreQualifiedCoverageTest do
  use ExUnit.Case, async: true

  alias Elmx.Backend.ElixirCodegen.Emit
  alias Elmx.Backend.ElixirCodegen.Emit.Qualified

  @c_codegen Path.expand("../../elmc/lib/elmc/backend/c_codegen.ex", __DIR__)

  test "every elmc special_value_from_target for elm/core modules compiles in elmx" do
    entries = core_special_entries()

    env =
      Emit.function_env("Main", [])
      |> Map.put(:module, "Main")
      |> Map.put(:zero_arity_fns, MapSet.new())
      |> Map.put(:function_arities, %{})
      |> Map.put(:constructor_lookup, %{})

    missing =
      Enum.filter(entries, fn {target, arity} ->
        args = dummy_args(arity)

        try do
          Qualified.compile_qualified_call(
            %{op: :qualified_call, target: target, args: args},
            env,
            0
          )

          false
        rescue
          _ -> true
        end
      end)
      |> Enum.sort()

    assert missing == [],
           """
           Missing #{length(missing)} elm/core qualified_call compile path(s):
           #{Enum.map_join(missing, "\n", fn {t, a} -> "  #{t} @ arity #{a}" end)}
           """
  end

  defp core_special_entries do
    @c_codegen
    |> File.read!()
    |> then(
      &Regex.scan(~r/special_value_from_target\("([^"]+)",\s*\[([^\]]*)\]\)/, &1,
        capture: :all_but_first
      )
    )
    |> Enum.flat_map(fn [target, args] ->
      if core_module?(target) do
        arity = if String.trim(args) == "", do: 0, else: args |> String.split(",") |> length()
        [{target, arity}]
      else
        []
      end
    end)
    |> Enum.uniq()
  end

  defp core_module?(target) do
    case String.split(target, ".", parts: 2) do
      [mod, _] ->
        mod in [
          "Basics",
          "List",
          "String",
          "Maybe",
          "Result",
          "Dict",
          "Set",
          "Array",
          "Char",
          "Tuple",
          "Debug",
          "Task",
          "Process",
          "Bitwise",
          "Random"
        ]

      _ ->
        false
    end
  end

  defp dummy_args(0), do: []

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
