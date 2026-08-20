defmodule Elmc.PlanStringLengthNativeTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.C.Lower.Function, as: CLowerFunction
  alias Elmc.Backend.Plan.Lower.Function, as: PlanLower

  @moduletag :plan_surface

  test "String.length consumed as Int emits native length for any function name" do
    for name <- ["fitsLine", "roomLeft"] do
      decl = length_sum_decl(name)

      Process.put(:elmc_program_decls, %{{"Main", name} => decl})
      Process.put(:elmc_codegen_opts, %{plan_ir_mode: :primary})

      assert {:ok, plan} =
               PlanLower.lower(decl, "Main", %{{"Main", name} => decl}, rc_required: true)

      c = CLowerFunction.emit(plan)
      assert c =~ "elmc_string_length("
      refute c =~ "elmc_new_int"
      refute c =~ "elmc_as_int("
    end
  end

  defp length_sum_decl(name) when is_binary(name) do
    %{
      name: name,
      args: ["line", "word", "maxChars"],
      type: "String -> String -> Int -> Bool",
      expr: %{
        op: :compare,
        kind: :lt,
        left: %{
          op: :call,
          name: "__add__",
          args: [
            %{
              op: :call,
              name: "__add__",
              args: [
                %{op: :string_length_expr, arg: %{op: :var, name: "line"}},
                %{op: :int_literal, value: 1}
              ]
            },
            %{op: :string_length_expr, arg: %{op: :var, name: "word"}}
          ]
        },
        right: %{op: :var, name: "maxChars"}
      }
    }
  end
end
