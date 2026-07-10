defmodule Elmc.CompanionSendFoldTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.CompanionSendFold

  setup do
    Process.put(:elmc_program_decls, %{
      {"Companion.Internal", "watchToPhoneTag"} => %{
        expr: %{
          op: :case,
          branches: [
            %{
              pattern: %{kind: :constructor, name: "RequestSunData", tag: 2},
              expr: %{op: :int_literal, value: 3}
            },
            %{
              pattern: %{kind: :constructor, name: "RequestWeather", tag: 3},
              expr: %{op: :int_literal, value: 4}
            }
          ]
        }
      },
      {"Companion.Internal", "watchToPhoneValue"} => %{
        expr: %{
          op: :case,
          branches: [
            %{
              pattern: %{kind: :constructor, name: "RequestSunData", tag: 2},
              expr: %{op: :int_literal, value: 0}
            },
            %{
              pattern: %{kind: :constructor, name: "RequestWeather", tag: 3},
              expr: %{op: :int_literal, value: 0}
            }
          ]
        }
      }
    })

    Process.put(:elmc_constructor_tags, %{"RequestSunData" => 2, "RequestWeather" => 3})

    on_exit(fn ->
      Process.delete(:elmc_program_decls)
      Process.delete(:elmc_constructor_tags)
    end)

    :ok
  end

  test "fold_wire_params resolves nullary companion constructors" do
    assert {:ok, 3, 0} =
             CompanionSendFold.fold_wire_params(%{
               op: :constructor_call,
               target: "RequestSunData",
               args: []
             })

    assert {:ok, 4, 0} =
             CompanionSendFold.fold_wire_params(%{
               op: :constructor_call,
               target: "RequestWeather",
               args: []
             })
  end

  test "fold_wire_params returns error when lookup tables are not int-literal cases" do
    Process.put(:elmc_program_decls, %{
      {"Companion.Internal", "watchToPhoneTag"} => %{
        expr: %{
          op: :case,
          branches: [
            %{
              pattern: %{kind: :constructor, name: "RequestSunData", tag: 2},
              expr: %{op: :var, name: "tag"}
            }
          ]
        }
      },
      {"Companion.Internal", "watchToPhoneValue"} => %{
        expr: %{
          op: :case,
          branches: [
            %{
              pattern: %{kind: :constructor, name: "RequestSunData", tag: 2},
              expr: %{op: :int_literal, value: 0}
            }
          ]
        }
      }
    })

    assert :error =
             CompanionSendFold.fold_wire_params(%{
               op: :constructor_call,
               target: "RequestSunData",
               args: []
             })
  end
end
