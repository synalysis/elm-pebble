defmodule Elmc.ListPatternConditionTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.Patterns

  test "List Point case patterns stay compact (no layout cross-product explosion)" do
    env = %{
      __module__: "Main",
      __function_name__: "polygonLines",
      __var_types__: %{"points" => "List Point"}
    }

    pattern = %{
      kind: :constructor,
      name: "::",
      arg_pattern: %{
        kind: :tuple,
        elements: [
          %{kind: :var, name: "a"},
          %{
            kind: :constructor,
            name: "::",
            arg_pattern: %{
              kind: :tuple,
              elements: [
                %{kind: :var, name: "b"},
                %{
                  kind: :constructor,
                  name: "::",
                  arg_pattern: %{
                    kind: :tuple,
                    elements: [
                      %{kind: :var, name: "c"},
                      %{kind: :constructor, name: "[]"}
                    ]
                  }
                }
              ]
            }
          }
        ]
      }
    }

    code = Patterns.pattern_condition("points", pattern, env)

    assert byte_size(code) < 8_000
    refute String.contains?(code, "ELMC_TAG_INT_LIST")
    refute String.contains?(code, "ELMC_TAG_FLOAT_LIST")
    refute String.contains?(code, "ELMC_TAG_RECORD_SEQ")
  end

  test "List Int compact param uses a single int-list layout branch per depth" do
    env = %{
      __module__: "Main",
      __function_name__: "decode",
      __var_types__: %{"coords" => "List Int"}
    }

    Process.put(:elmc_storage_plans, %{
      param_plans: %{{"Main", "decode", "coords"} => Elmc.Backend.CCodegen.StoragePlan.int_compact()},
      field_plans: %{},
      binding_plans: %{}
    })

    on_exit(fn -> Process.delete(:elmc_storage_plans) end)

    pattern = %{
      kind: :constructor,
      name: "::",
      arg_pattern: %{
        kind: :tuple,
        elements: [
          %{kind: :int, value: 1},
          %{
            kind: :constructor,
            name: "::",
            arg_pattern: %{
              kind: :tuple,
              elements: [
                %{kind: :int, value: 2},
                %{kind: :constructor, name: "[]"}
              ]
            }
          }
        ]
      }
    }

    code = Patterns.pattern_condition("coords", pattern, env)

    assert byte_size(code) < 4_000
    assert String.contains?(code, "ELMC_TAG_INT_LIST")
    refute String.contains?(code, "ELMC_TAG_FLOAT_LIST")
    refute String.contains?(code, "ELMC_TAG_RECORD_SEQ")
  end
end
