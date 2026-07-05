defmodule Elmc.ListPatternRcTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.Patterns
  alias Elmc.Backend.CCodegen.StoragePlan

  defp rc_env(name, type, layout, elem) do
    Process.put(:elmc_storage_plans, %{
      binding_plans: %{
        {"Main", "fn", name} => %StoragePlan{elem: elem, layout: layout}
      }
    })

    %{
      __rc_catch__: true,
      __rc_required__: true,
      __module__: "Main",
      __function_name__: "fn",
      __var_types__: %{name => type}
    }
  end

  defp cons_pattern(head, tail) do
    %{
      kind: :constructor,
      name: "::",
      arg_pattern: %{kind: :tuple, elements: [head, tail]}
    }
  end

  setup do
    on_exit(fn -> Process.delete(:elmc_storage_plans) end)
    :ok
  end

  test "RC int_spine cons pattern conditions avoid value-returning take wrappers" do
    pattern =
      cons_pattern(
        %{kind: :int, value: 7},
        %{kind: :constructor, name: "[]"}
      )

    cond = Patterns.pattern_condition("cells", pattern, rc_env("cells", "List Int", :native_linked, {:primitive, :int}))

    assert cond =~ "ELMC_TAG_INT_SPINE"
    assert cond =~ "->head == 7"
    refute cond =~ "_take("
  end

  test "RC float_list cons pattern conditions avoid value-returning take wrappers" do
    pattern =
      cons_pattern(
        %{kind: :int, value: 3},
        %{kind: :constructor, name: "[]"}
      )

    cond =
      Patterns.pattern_condition(
        "values",
        pattern,
        rc_env("values", "List Float", :compact, {:primitive, :float})
      )

    assert cond =~ "ELMC_TAG_FLOAT_LIST"
    assert cond =~ "->values[0]"
    refute cond =~ "_take("
  end

  test "RC record_seq cons pattern conditions avoid value-returning take wrappers" do
    pattern =
      cons_pattern(
        %{kind: :var, name: "point"},
        %{kind: :constructor, name: "[]"}
      )

    cond =
      Patterns.pattern_condition(
        "values",
        pattern,
        rc_env("values", "List Point", :compact, {:record, "Point", ["x", "y"]})
      )

    assert cond =~ "ELMC_TAG_RECORD_SEQ"
    refute cond =~ "_take("
  end

  test "RC bind_pattern on List Int cons hoists suffix via elmc_list_drop_int" do
    alias Elmc.Backend.CCodegen.CaseCompile
    alias Elmc.Backend.CCodegen.RcRuntimeEmit
    alias Elmc.Backend.CCodegen.ValueSlots

    ValueSlots.reset(epilogue_lifo: true)

    pattern =
      cons_pattern(
        %{kind: :var, name: "h"},
        %{kind: :var, name: "t"}
      )

    env =
      rc_env("cells", "List Int", :compact, {:primitive, :int})
      |> Map.put(:__bind_counter__, 0)

    out = RcRuntimeEmit.function_out_ref()

    env =
      env
      |> Map.put(:__branch_out__, out)
      |> Map.put(:__declared_outs__, MapSet.new([out]))

    env = Patterns.bind_pattern(env, pattern, "cells")

    {expr_code, assignment_code, _counter} =
      CaseCompile.branch_assignment(%{op: :int_literal, value: 0}, out, env, 0)

    body = expr_code <> assignment_code

    assert body =~ "elmc_list_drop_int"
    assert body =~ "CHECK_RC(Rc)"
    refute body =~ "_take("
  end

  test "non-RC list cons conditions may still use take wrappers for legacy modes" do
    pattern =
      cons_pattern(
        %{kind: :int, value: 1},
        %{kind: :constructor, name: "[]"}
      )

    Process.put(:elmc_storage_plans, %{
      binding_plans: %{
        {"Main", "cells", "cells"} => %StoragePlan{
          elem: {:primitive, :int},
          layout: :native_linked
        }
      }
    })

    env = %{
      __module__: "Main",
      __function_name__: "cells",
      __var_types__: %{"cells" => "List Int"}
    }

    cond = Patterns.pattern_condition("cells", pattern, env)

    assert cond =~ "elmc_int_spine_head_boxed_take"
  end
end
