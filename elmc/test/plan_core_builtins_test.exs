defmodule Elmc.PlanCoreBuiltinsTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Plan.Lower.Function
  alias Elmc.Backend.Plan.RuntimeBuiltins

  @moduletag :plan_surface

  defp lower_expr(expr, params \\ []) do
    decl = %{
      name: "probe",
      args: params,
      expr: expr
    }

    decl_map = %{{"Probe", "probe"} => decl}

    assert {:ok, plan} = Function.lower(decl, "Probe", decl_map, rc_required: true)
    plan
  end

  test "RuntimeBuiltins maps elm/core truncate and bitwise symbols" do
    assert RuntimeBuiltins.from_c_symbol("elmc_basics_truncate") == :basics_truncate
    assert RuntimeBuiltins.from_c_symbol("elmc_bitwise_and") == :bitwise_and
    assert RuntimeBuiltins.from_c_symbol("elmc_dict_insert") == :dict_insert
    assert RuntimeBuiltins.from_c_symbol("elmc_string_from_int") == :string_from_int_value
    assert RuntimeBuiltins.from_c_symbol("elmc_basics_sqrt") == :basics_sqrt
    assert RuntimeBuiltins.from_c_symbol("elmc_list_map4") == :list_map4
    assert RuntimeBuiltins.from_c_symbol("elmc_json_decode_map") == :json_decode_map
    assert RuntimeBuiltins.from_c_symbol("elmc_time_now_millis") == :time_now_millis
    assert RuntimeBuiltins.from_c_symbol("elmc_append") == :append
  end

  test "special_values runtime symbols are registered in RuntimeBuiltins" do
    special_dir = Path.expand("../lib/elmc/backend/c_codegen/special_values", __DIR__)

    symbols =
      Path.wildcard(special_dir <> "/**/*.ex")
      |> Enum.flat_map(fn path ->
        path
        |> File.read!()
        |> then(&Regex.scan(~r/"elmc_[a-z0-9_]+"/, &1))
        |> Enum.map(fn [quoted] -> String.trim(quoted, "\"") end)
      end)
      |> Enum.uniq()
      |> Enum.sort()

    missing =
      Enum.filter(symbols, fn sym ->
        RuntimeBuiltins.from_c_symbol(sym) == nil
      end)

    assert missing == [],
           "missing RuntimeBuiltins for #{length(missing)} special_values symbols: #{inspect(Enum.take(missing, 12))}"
  end

  test "Basics.sqrt lowers through plan" do
    plan =
      lower_expr(%{
        op: :qualified_call,
        target: "Basics.sqrt",
        args: [%{op: :float_literal, value: 9.0}]
      })

    assert inspect(plan.blocks) =~ "basics_sqrt"
  end

  test "List.map4 lowers through plan" do
    plan =
      lower_expr(%{
        op: :qualified_call,
        target: "List.map4",
        args: [
          %{op: :lambda, args: ["a", "b", "c", "d"], body: %{op: :int_literal, value: 0}},
          %{op: :list_literal, items: []},
          %{op: :list_literal, items: []},
          %{op: :list_literal, items: []},
          %{op: :list_literal, items: []}
        ]
      })

    assert inspect(plan.blocks) =~ "list_map4"
  end

  test "Basics.truncate lowers through plan" do
    plan =
      lower_expr(%{
        op: :qualified_call,
        target: "Basics.truncate",
        args: [%{op: :float_literal, value: 3.9}]
      })

    body = inspect(plan.blocks)
    assert body =~ "basics_truncate"
  end

  test "Bitwise.and lowers through plan" do
    plan =
      lower_expr(%{
        op: :qualified_call,
        target: "Bitwise.and",
        args: [%{op: :int_literal, value: 5}, %{op: :int_literal, value: 3}]
      })

    assert inspect(plan.blocks) =~ "bitwise_and"
  end

  test "List.member lowers through plan" do
    plan =
      lower_expr(%{
        op: :qualified_call,
        target: "List.member",
        args: [%{op: :int_literal, value: 2}, %{op: :list_literal, items: [%{op: :int_literal, value: 1}]}]
      })

    assert inspect(plan.blocks) =~ "list_member"
  end

  test "string_length_expr lowers through plan" do
    plan =
      lower_expr(%{
        op: :string_length_expr,
        arg: %{op: :string_literal, value: "abc"}
      })

    assert inspect(plan.blocks) =~ "string_length_boxed"
  end

  test "char_from_code_expr lowers through plan" do
    plan =
      lower_expr(%{
        op: :char_from_code_expr,
        arg: %{op: :int_literal, value: 65}
      })

    assert inspect(plan.blocks) =~ "char_from_code"
  end

  test "Order LT constructor lowers through plan" do
    plan =
      lower_expr(%{
        op: :constructor_call,
        target: "LT",
        args: []
      })

    assert inspect(plan.blocks) =~ "new_order"
  end

  test "partial (+) lowers to two-arg lambda" do
    plan =
      lower_expr(%{
        op: :call,
        name: "__add__",
        args: []
      })

    assert plan.lambdas != []
    assert inspect(plan.blocks) =~ "make_closure"
  end

  test "operator var __add__ lowers to two-arg lambda" do
    plan =
      lower_expr(%{
        op: :var,
        name: "__add__"
      })

    assert plan.lambdas != []
    assert inspect(plan.blocks) =~ "make_closure"
  end

  test "deep dotted var lowers chained record_get" do
    decl = %{
      name: "probe",
      args: ["model"],
      expr: %{op: :var, name: "model.extras.stringOk"}
    }

    decl_map = %{{"Probe", "probe"} => decl}

    assert {:ok, plan} = Function.lower(decl, "Probe", decl_map, rc_required: true)
    text = inspect(plan.blocks)
    assert text =~ "record_get"
    assert String.split(text, "record_get") |> length() >= 3
  end

  test "compose_left lowers to lambda closure" do
    plan =
      lower_expr(%{
        op: :compose_left,
        f: %{op: :qualified_ref, target: "Basics.negate"},
        g: %{op: :qualified_ref, target: "Basics.abs"}
      })

    assert plan.lambdas != []
    assert inspect(plan.blocks) =~ "make_closure"
  end

  test "String.contains lowers through plan runtime_call" do
    plan =
      lower_expr(%{
        op: :qualified_call,
        target: "String.contains",
        args: [
          %{op: :string_literal, value: "needle"},
          %{op: :string_literal, value: "hayneedle"}
        ]
      })

    assert inspect(plan.blocks) =~ "string_contains"
  end

  test "String.slice lowers through qualified binary map" do
    plan =
      lower_expr(%{
        op: :qualified_call,
        target: "String.slice",
        args: [
          %{op: :string_literal, value: "abcdef"},
          %{op: :int_literal, value: 1}
        ]
      })

    assert inspect(plan.blocks) =~ "string_slice"
  end

  test "List.sortBy lowers through qualified binary map" do
    plan =
      lower_expr(%{
        op: :qualified_call,
        target: "List.sortBy",
        args: [
          %{op: :lambda, args: ["x"], body: %{op: :var, name: "x"}},
          %{op: :list_literal, items: [%{op: :int_literal, value: 3}]}
        ]
      })

    assert inspect(plan.blocks) =~ "list_sort_by"
  end

  test "List.partition lowers through qualified binary map" do
    plan =
      lower_expr(%{
        op: :qualified_call,
        target: "List.partition",
        args: [
          %{op: :lambda, args: ["x"], body: %{op: :bool_literal, value: true}},
          %{op: :list_literal, items: [%{op: :int_literal, value: 1}]}
        ]
      })

    assert inspect(plan.blocks) =~ "list_partition"
  end

  test "List.map with record update in lambda lowers through closure list_map" do
    plan =
      lower_expr(
        %{
          op: :qualified_call,
          target: "List.map",
          args: [
            %{
              op: :lambda,
              args: ["cell"],
              body: %{
                op: :record_update,
                base: %{op: :var, name: "cell"},
                fields: [
                  %{
                    name: "score",
                    expr: %{
                      op: :call,
                      name: "__add__",
                      args: [
                        %{op: :field_access, arg: %{op: :var, name: "cell"}, field: "score"},
                        %{op: :int_literal, value: 1}
                      ]
                    }
                  }
                ]
              }
            },
            %{op: :list_literal, items: []}
          ]
        },
        []
      )

    text = inspect(plan.blocks)
    assert text =~ "list_map" or text =~ "make_closure"
  end

  test "Task.map lowers task_map runtime builtin" do
    plan =
      lower_expr(%{
        op: :qualified_call,
        target: "Task.map",
        args: [
          %{op: :lambda, args: ["n"], body: %{op: :var, name: "n"}},
          %{op: :qualified_call, target: "Task.succeed", args: [%{op: :int_literal, value: 11}]}
        ]
      })

    assert inspect(plan.blocks) =~ "task_map"
    refute inspect(plan.blocks) =~ "builtin: nil"
  end

  test "Task.andThen lowers task_and_then runtime builtin" do
    plan =
      lower_expr(%{
        op: :qualified_call,
        target: "Task.andThen",
        args: [
          %{op: :lambda, args: ["n"], body: %{op: :var, name: "n"}},
          %{op: :qualified_call, target: "Task.succeed", args: [%{op: :int_literal, value: 2}]}
        ]
      })

    assert inspect(plan.blocks) =~ "task_and_then"
  end

  test "Result.withDefault lowers result_with_default runtime builtin" do
    Process.put(:elmc_constructor_tags, %{"Ok" => 0, "Err" => 1})

    plan =
      lower_expr(%{
        op: :qualified_call,
        target: "Result.withDefault",
        args: [
          %{op: :int_literal, value: 0},
          %{op: :constructor_call, target: "Ok", args: [%{op: :int_literal, value: 42}]}
        ]
      })

    assert inspect(plan.blocks) =~ "result_with_default"
  end

  test "nested let_in with List.foldl lowers through plan" do
    plan =
      lower_expr(%{
        op: :let_in,
        name: "acc",
        value_expr: %{op: :int_literal, value: 0},
        in_expr: %{
          op: :let_in,
          name: "items",
          value_expr: %{
            op: :list_literal,
            items: [%{op: :int_literal, value: 1}, %{op: :int_literal, value: 2}]
          },
          in_expr: %{
            op: :qualified_call,
            target: "List.foldl",
            args: [
              %{
                op: :lambda,
                args: ["x", "a"],
                body: %{
                  op: :call,
                  name: "__add__",
                  args: [%{op: :var, name: "x"}, %{op: :var, name: "a"}]
                }
              },
              %{op: :var, name: "acc"},
              %{op: :var, name: "items"}
            ]
          }
        }
      })

    text = inspect(plan.blocks)
    assert text =~ "list_foldl"
    assert plan.lambdas != []
  end

  test "unknown qualified ternary calls lower to call_fn not nil builtin" do
    helper_decl = %{
      name: "scale",
      args: ["a", "b", "c"],
      type: "Int",
      expr: %{
        op: :call,
        name: "__add__",
        args: [%{op: :var, name: "a"}, %{op: :var, name: "b"}]
      }
    }

    decl = %{
      name: "probe",
      args: [],
      expr: %{
        op: :qualified_call,
        target: "Probe.scale",
        args: [
          %{op: :int_literal, value: 1},
          %{op: :int_literal, value: 2},
          %{op: :int_literal, value: 3}
        ]
      }
    }

    decl_map = %{
      {"Probe", "scale"} => helper_decl,
      {"Probe", "probe"} => decl
    }

    assert {:ok, plan} = Function.lower(decl, "Probe", decl_map, rc_required: true)

    instrs = Enum.flat_map(plan.blocks, & &1.instrs)
    assert Enum.any?(instrs, &(&1.op == :call_fn))

    refute Enum.any?(instrs, fn
           %{op: :call_runtime, args: %{builtin: builtin}} -> is_nil(builtin)
           _ -> false
         end)
  end
end
