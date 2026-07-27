defmodule Elmc.PlanLetFreeVarsRecursionTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.Lower.Function

  test "nested let binder name does not force letrec against later sibling" do
    # Scene3d.toWebGLEntities: `(toneMapType, toneMapParam) = case …` expands to a
    # tuple bind whose value is `let caseSubject = … in case caseSubject of …`,
    # while a later sibling binding is also named `caseSubject`.
    expr = %{
      op: :let_in,
      name: "__tupleBind_a_b",
      value_expr: %{
        op: :let_in,
        name: "caseSubject",
        value_expr: %{op: :field_access, arg: "arguments", field: "toneMapping"},
        in_expr: %{
          op: :case,
          subject: "caseSubject",
          branches: [
            %{
              pattern: %{kind: :wildcard},
              expr: %{
                op: :tuple2,
                left: %{op: :int_literal, value: 0},
                right: %{op: :int_literal, value: 0}
              }
            }
          ]
        }
      },
      in_expr: %{
        op: :let_in,
        name: "a",
        value_expr: %{
          op: :qualified_call,
          target: "Tuple.first",
          args: [%{op: :var, name: "__tupleBind_a_b"}]
        },
        in_expr: %{
          op: :let_in,
          name: "b",
          value_expr: %{
            op: :qualified_call,
            target: "Tuple.second",
            args: [%{op: :var, name: "__tupleBind_a_b"}]
          },
          in_expr: %{
            op: :let_in,
            name: "caseSubject",
            value_expr: %{op: :int_literal, value: 1},
            in_expr: %{op: :var, name: "a"}
          }
        }
      }
    }

    decl = %{name: "probe", args: ["arguments"], expr: expr}
    Process.delete(:elmc_plan_unsupported_reasons)

    assert {:ok, _plan} =
             Function.lower(decl, "Main", %{{"Main", "probe"} => decl}, rc_required: false)
  end
end
