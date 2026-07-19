defmodule Elmc.WasmLowerTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.Builder
  alias Elmc.Backend.Wasm.Lower

  @forbidden ~w(owned[ CHECK_RC CATCH_BEGIN ELMC_RELEASE)

  test "lower emits WAT module without C-specific tokens" do
    plan =
      Builder.new("Test", "wasm", args: [], rc_required: true)
      |> Builder.catch_begin()
      |> then(fn b ->
        {reg, b1} = Builder.fresh_reg(b)

        {_, b2} =
          Builder.emit(b1, :call_runtime, %{
            dest: reg,
            args: %{builtin: :new_int, args: [], literal: 7},
            effects: Elmc.Backend.Plan.Types.fallible_effects(reg)
          })

        b2
      end)
      |> Builder.catch_end()
      |> then(fn b ->
        b1 = Builder.emit_ret(b, 0)
        Builder.to_function_plan(b1)
      end)

    assert {:ok, module_map} = Lower.lower(plan)
    wat = Lower.render_wat(module_map)

    Enum.each(@forbidden, fn token ->
      refute wat =~ token, "WAT must not contain C-specific #{token}"
    end)

    assert wat =~ "(module"
    assert wat =~ "runtime_new_int"
  end

  test "RC ret clears owned after moving boxed result into fn_out" do
    plan =
      Builder.new("Test", "owned_publish", args: [], rc_required: true)
      |> Builder.catch_begin()
      |> then(fn b ->
        {reg, b1} = Builder.fresh_reg(b)

        {_, b2} =
          Builder.emit(b1, :call_runtime, %{
            dest: reg,
            args: %{builtin: :new_int, args: [], literal: 3},
            effects: Elmc.Backend.Plan.Types.fallible_effects(reg)
          })

        b2
      end)
      |> Builder.catch_end()
      |> then(fn b ->
        Builder.to_function_plan(Builder.emit_ret(b, 0))
      end)

    assert {:ok, module_map} = Lower.lower(plan)
    wat = Lower.render_wat(module_map)

    # RC epilogue releases surviving owned slots via reachability-aware helper.
    assert wat =~ ~r/call \$runtime_release_unless_reachable/
    # Owned slot nulled after move into $fn_out.
    assert wat =~ ~r/local\.set \$owned\d+ \(i32\.const 0\)/
  end

  test "RC ownership-transfer consume nulls owned without release" do
    plan =
      Builder.new("Test", "owned_take", args: [], rc_required: true)
      |> Builder.catch_begin()
      |> then(fn b ->
        {a, b1} = Builder.fresh_reg(b)
        {b_reg, b2} = Builder.fresh_reg(b1)
        {dest, b3} = Builder.fresh_reg(b2)

        {_, b4} =
          Builder.emit(b3, :call_runtime, %{
            dest: a,
            args: %{builtin: :new_int, args: [], literal: 1},
            effects: Elmc.Backend.Plan.Types.fallible_effects(a)
          })

        {_, b5} =
          Builder.emit(b4, :call_runtime, %{
            dest: b_reg,
            args: %{builtin: :new_int, args: [], literal: 2},
            effects: Elmc.Backend.Plan.Types.fallible_effects(b_reg)
          })

        {_, b6} =
          Builder.emit(b5, :call_runtime, %{
            dest: dest,
            args: %{builtin: :tuple2_take, args: [a, b_reg]},
            effects: %{
              produces: {:owned, dest},
              consumes: [a, b_reg],
              borrows: [],
              fallible: true
            }
          })

        b6
      end)
      |> Builder.catch_end()
      |> then(fn b ->
        Builder.to_function_plan(Builder.emit_ret(b, 2))
      end)

    assert {:ok, module_map} = Lower.lower(plan)
    wat = Lower.render_wat(module_map)

    # Transfer: null owned args after take (no mid-body release of those slots).
    assert wat =~ ~r/local\.set \$owned\d+ \(i32\.const 0\)/
    assert wat =~ "tuple2"
  end

  test "lower_many links multiple functions" do
    plan_a =
      Builder.new("A", "f", args: [])
      |> then(fn b ->
        {reg, b1} = Builder.emit_const_int(b, 1)
        b2 = Builder.emit_ret(b1, reg)
        Builder.to_function_plan(b2)
      end)

    plan_b =
      Builder.new("B", "g", args: [])
      |> then(fn b ->
        {reg, b1} = Builder.emit_const_int(b, 2)
        b2 = Builder.emit_ret(b1, reg)
        Builder.to_function_plan(b2)
      end)

    assert {:ok, module_map} = Lower.lower_many([plan_a, plan_b])
    wat = Lower.render_wat(module_map)
    assert wat =~ "elmc_fn_A_f"
    assert wat =~ "elmc_fn_B_g"
  end

  test "boxed float sub_vars lowers to f32.sub and new_float" do
    plan =
      Builder.new("Test", "float_sub", args: ["a", "b"], rc_required: true)
      |> Builder.catch_begin()
      |> then(fn b ->
        {a, b1} = Builder.get_or_load_param(b, 0, "a")
        {b_reg, b2} = Builder.get_or_load_param(b1, 1, "b")
        {dest, b3} = Builder.fresh_reg(b2)

        {_, b4} =
          Builder.emit(b3, :int_arith, %{
            dest: dest,
            args: %{kind: :sub_vars, lhs: a, rhs: b_reg},
            effects: Elmc.Backend.Plan.Types.fallible_effects(dest, [a, b_reg])
          })

        b4
      end)
      |> Builder.catch_end()
      |> then(fn b ->
        Builder.to_function_plan(Builder.emit_ret(b, 0))
      end)

    assert {:ok, module_map} = Lower.lower(plan)
    wat = Lower.render_wat(module_map)

    assert wat =~ "runtime_as_float"
    assert wat =~ "f32.sub"
    assert wat =~ "i32.reinterpret_f32"
    assert wat =~ "runtime_new_float"
    refute wat =~ ";; boxed_binop dynamic"
  end

  test "float int_arith chain keeps add_const on f32 path after sub_vars" do
    plan =
      Builder.new("Test", "float_chain", args: ["a", "b"], rc_required: true)
      |> Builder.catch_begin()
      |> then(fn b ->
        {a, b1} = Builder.get_or_load_param(b, 0, "a")
        {b_reg, b2} = Builder.get_or_load_param(b1, 1, "b")
        {width, b3} = Builder.fresh_reg(b2)
        {padded, b4} = Builder.fresh_reg(b3)

        {_, b5} =
          Builder.emit(b4, :int_arith, %{
            dest: width,
            args: %{kind: :sub_vars, lhs: a, rhs: b_reg},
            effects: Elmc.Backend.Plan.Types.fallible_effects(width, [a, b_reg])
          })

        {_, b6} =
          Builder.emit(b5, :int_arith, %{
            dest: padded,
            args: %{kind: :add_const, lhs: width, value: 4},
            effects: Elmc.Backend.Plan.Types.fallible_effects(padded, [width])
          })

        b6
      end)
      |> Builder.catch_end()
      |> then(fn b ->
        Builder.to_function_plan(Builder.emit_ret(b, 0))
      end)

    assert {:ok, module_map} = Lower.lower(plan)
    wat = Lower.render_wat(module_map)

    assert wat =~ "f32.sub"
    assert wat =~ "f32.add"
    refute wat =~ "i32.add"
  end

  test "boxed Int compare unboxes operands before i32.gt_s" do
    plan =
      Builder.new("Test", "int_boxed_compare", args: [], rc_required: false)
      |> then(fn b ->
        {len_reg, b1} = Builder.fresh_reg(b)
        {right_reg, b2} = Builder.fresh_reg(b1)
        {dest, b3} = Builder.fresh_reg(b2)

        {_, b4} =
          Builder.emit(b3, :call_runtime, %{
            dest: len_reg,
            args: %{builtin: :new_int, args: [], literal: 1},
            effects: Elmc.Backend.Plan.Types.empty_effects()
          })

        {_, b5} =
          Builder.emit(b4, :call_runtime, %{
            dest: right_reg,
            args: %{builtin: :new_int, args: [], literal: 16},
            effects: Elmc.Backend.Plan.Types.empty_effects()
          })

        {_, b6} =
          Builder.emit(b5, :compare, %{
            dest: dest,
            args: %{kind: :gt, left: len_reg, right: right_reg, mode: :int_boxed},
            effects: Elmc.Backend.Plan.Types.empty_effects()
          })

        Builder.to_function_plan(Builder.emit_ret(b6, 0))
      end)

    assert {:ok, module_map} = Lower.lower(plan)
    wat = Lower.render_wat(module_map)

    assert wat =~ "runtime_as_int"
    assert wat =~ "i32.gt_s"
    refute wat =~ ~r/local\.get \$reg\d+\)\s*\n\s*\(i32\.gt_s\s+\(local\.get \$reg/
  end
end
