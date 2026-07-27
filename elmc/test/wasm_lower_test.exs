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

  test "boxed float sub via boxed_binop lowers to f32.sub and new_float" do
    plan =
      Builder.new("Test", "float_sub", args: ["a", "b"], rc_required: true)
      |> Builder.catch_begin()
      |> then(fn b ->
        {a, b1} = Builder.get_or_load_param(b, 0, "a")
        {b_reg, b2} = Builder.get_or_load_param(b1, 1, "b")
        {dest, b3} = Builder.fresh_reg(b2)

        {_, b4} =
          Builder.emit(b3, :boxed_binop, %{
            dest: dest,
            args: %{op: :sub, lhs: a, rhs: b_reg, mode: :float},
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

  test "fdiv of native int consts uses float_div_bits not i32.const 0" do
    # Color.rgb255: scaleFrom255 c = toFloat c / 255. When both sides look like
    # native ints, the old native-int binop path emitted i32.const 0 for :fdiv.
    plan =
      Builder.new("Test", "scale_from_255", args: [], rc_required: true)
      |> Builder.catch_begin()
      |> then(fn b ->
        {c, b1} = Builder.emit_const_int(b, 15)
        {denom, b2} = Builder.emit_const_int(b1, 255)
        {dest, b3} = Builder.fresh_reg(b2)

        {_, b4} =
          Builder.emit(b3, :boxed_binop, %{
            dest: dest,
            args: %{op: :fdiv, lhs: c, rhs: denom},
            effects: Elmc.Backend.Plan.Types.fallible_effects(dest, [c, denom])
          })

        Builder.emit_ret(b4, dest)
      end)
      |> Builder.catch_end()
      |> then(&Builder.to_function_plan/1)

    assert {:ok, module_map} = Lower.lower(plan)
    wat = Lower.render_wat(module_map)

    assert wat =~ "runtime_float_div_bits"
    assert wat =~ "runtime_as_float"
    assert wat =~ "runtime_new_float"
    refute wat =~ ~r/\(i32\.const 0\)\s*\)\s*;; boxed_binop/
    # Must not be a bare zero result from the native-int fallback.
    refute Regex.match?(~r/\$r\d+\s+=\s+\(i32\.const 0\)/, wat) and
             not String.contains?(wat, "runtime_float_div_bits")
  end

  test "Float field * scale lowers via boxed f32.mul not as_int+i32.mul" do
    # Scene3d.updateViewBounds: modelCenterX = originalCenter.x * scale
    alias Elmc.Backend.Plan.{Builder, Context}
    alias Elmc.Backend.Plan.Lower.IntCall

    ctx =
      Context.new(
        module: "Scene3d",
        function_name: "updateViewBounds",
        params: ["scale", "originalCenter"],
        decl_map: %{},
        local_types: %{"scale" => "Float"},
        rc_required: true,
        fallible: true
      )

    b0 =
      Builder.new("Scene3d", "updateViewBounds",
        args: ["scale", "originalCenter"],
        rc_required: true,
        fallible: true
      )
      |> Builder.catch_begin()

    {_, b1} = Builder.get_or_load_param(b0, 0, "scale")
    {_, b2} = Builder.get_or_load_param(b1, 1, "originalCenter")

    expr = %{
      op: :call,
      name: "__mul__",
      args: [
        %{op: :field_access, arg: %{op: :var, name: "originalCenter"}, field: "x"},
        %{op: :var, name: "scale"}
      ]
    }

    assert {:ok, dest, b3} = IntCall.compile(expr, ctx, b2)
    plan = Builder.to_function_plan(Builder.emit_ret(Builder.catch_end(b3), dest))

    assert {:ok, module_map} = Lower.lower(plan)
    wat = Lower.render_wat(module_map)

    assert wat =~ "f32.mul"
    assert wat =~ "runtime_as_float"
    assert wat =~ "runtime_new_float"
    refute wat =~ ~r/i32\.mul\s+\(call \$runtime_as_int/
  end

  test "untyped Float param * int literal uses f32.mul (Color.toCssString pct)" do
    # Color.toCssString: pct x = ((x * 10000) |> round |> toFloat) / 100
    # When the lambda param is typed Float (from the enclosing signature /
    # call-site expected type), mul must stay on f32 — as_int truncates
    # 15/255≈0.058 → 0 and every channel becomes rgba(0%,…).
    alias Elmc.Backend.Plan.{Builder, Context}
    alias Elmc.Backend.Plan.Lower.IntCall

    ctx =
      Context.new(
        module: "Color",
        function_name: "toCssString_lam_0",
        params: ["x"],
        decl_map: %{},
        local_types: %{"x" => "Float"},
        rc_required: true,
        fallible: true
      )

    b0 =
      Builder.new("Color", "toCssString_lam_0", args: ["x"], rc_required: true, fallible: true)
      |> Builder.catch_begin()

    {_, b1} = Builder.get_or_load_param(b0, 0, "x")

    expr = %{
      op: :call,
      name: "__mul__",
      args: [%{op: :var, name: "x"}, %{op: :int_literal, value: 10000}]
    }

    assert {:ok, dest, b2} = IntCall.compile(expr, ctx, b1)
    plan = Builder.to_function_plan(Builder.emit_ret(Builder.catch_end(b2), dest))

    assert {:ok, module_map} = Lower.lower(plan)
    wat = Lower.render_wat(module_map)

    assert wat =~ "f32.mul"
    assert wat =~ "runtime_new_float"
    refute wat =~ ~r/i32\.mul\s+\(call \$runtime_as_int/
  end

  test "abs of field muls sum via f32.add (Scene3d.updateViewBounds dimensions)" do
    # xDimension = abs(modelX*i.x) + abs(modelY*i.y) + abs(modelZ*i.z)
    alias Elmc.Backend.Plan.{Builder, Context}
    alias Elmc.Backend.Plan.Lower.IntCall

    ctx =
      Context.new(
        module: "Scene3d",
        function_name: "updateViewBounds",
        params: ["a", "b"],
        decl_map: %{},
        local_types: %{},
        rc_required: true,
        fallible: true
      )

    b0 =
      Builder.new("Scene3d", "updateViewBounds",
        args: ["a", "b"],
        rc_required: true,
        fallible: true
      )
      |> Builder.catch_begin()

    {_, b1} = Builder.get_or_load_param(b0, 0, "a")
    {_, b2} = Builder.get_or_load_param(b1, 1, "b")

    abs_mul = fn left, right ->
      %{
        op: :call,
        name: "Basics.abs",
        args: [
          %{
            op: :call,
            name: "__mul__",
            args: [
              %{op: :field_access, arg: %{op: :var, name: left}, field: "x"},
              %{op: :field_access, arg: %{op: :var, name: right}, field: "x"}
            ]
          }
        ]
      }
    end

    expr = %{
      op: :call,
      name: "__add__",
      args: [abs_mul.("a", "b"), abs_mul.("a", "b")]
    }

    assert {:ok, dest, b3} = IntCall.compile(expr, ctx, b2)
    plan = Builder.to_function_plan(Builder.emit_ret(Builder.catch_end(b3), dest))

    assert {:ok, module_map} = Lower.lower(plan)
    wat = Lower.render_wat(module_map)

    assert wat =~ "f32.add"
    assert wat =~ "runtime_new_float"
    refute wat =~ ~r/i32\.add\s+\(call \$runtime_as_int/
  end

  test "int_arith add_vars of floatish regs lowers to f32.add not as_int" do
    # WebGL.Matrices.projectionMatrix: -(f + n) / (f - n) where f,n come from
    # Quantity tuple_proj. Plan may still emit int_arith; WASM must f32.add.
    plan =
      Builder.new("Test", "clip_sum", args: [], rc_required: true)
      |> Builder.catch_begin()
      |> then(fn b ->
        {f, b1} = Builder.fresh_reg(b)
        {n, b2} = Builder.fresh_reg(b1)
        {dest, b3} = Builder.fresh_reg(b2)

        {_, b4} =
          Builder.emit(b3, :call_runtime, %{
            dest: f,
            args: %{builtin: :new_float, literal: 2.5},
            effects: Elmc.Backend.Plan.Types.fallible_effects(f)
          })

        {_, b5} =
          Builder.emit(b4, :call_runtime, %{
            dest: n,
            args: %{builtin: :new_float, literal: 0.1},
            effects: Elmc.Backend.Plan.Types.fallible_effects(n)
          })

        {_, b6} =
          Builder.emit(b5, :int_arith, %{
            dest: dest,
            args: %{kind: :add_vars, lhs: f, rhs: n},
            effects: Elmc.Backend.Plan.Types.fallible_effects(dest, [f, n])
          })

        Builder.emit_ret(b6, dest)
      end)
      |> Builder.catch_end()
      |> then(&Builder.to_function_plan/1)

    assert {:ok, module_map} = Lower.lower(plan)
    wat = Lower.render_wat(module_map)

    assert wat =~ "f32.add"
    assert wat =~ "runtime_new_float"
    refute wat =~ ~r/i32\.add\s+\(call \$runtime_as_int/
  end

  test "float boxed_binop chain keeps add on f32 path after sub" do
    plan =
      Builder.new("Test", "float_chain", args: ["a", "b"], rc_required: true)
      |> Builder.catch_begin()
      |> then(fn b ->
        {a, b1} = Builder.get_or_load_param(b, 0, "a")
        {b_reg, b2} = Builder.get_or_load_param(b1, 1, "b")
        {width, b3} = Builder.fresh_reg(b2)
        {padded, b4} = Builder.fresh_reg(b3)
        {four, b5} = Builder.fresh_reg(b4)

        {_, b6} =
          Builder.emit(b5, :boxed_binop, %{
            dest: width,
            args: %{op: :sub, lhs: a, rhs: b_reg, mode: :float},
            effects: Elmc.Backend.Plan.Types.fallible_effects(width, [a, b_reg])
          })

        {_, b7} =
          Builder.emit(b6, :call_runtime, %{
            dest: four,
            args: %{builtin: :new_float, literal: 4.0},
            effects: Elmc.Backend.Plan.Types.fallible_effects(four, [])
          })

        {_, b8} =
          Builder.emit(b7, :boxed_binop, %{
            dest: padded,
            args: %{op: :add, lhs: width, rhs: four, mode: :float},
            effects: Elmc.Backend.Plan.Types.fallible_effects(padded, [width, four])
          })

        b8
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

  test "boxed Int int_arith sub_const uses as_int and new_int (not f32)" do
    plan =
      Builder.new("Test", "int_sub_const", args: ["n"], rc_required: true)
      |> Builder.catch_begin()
      |> then(fn b ->
        {n, b1} = Builder.get_or_load_param(b, 0, "n")
        {dest, b2} = Builder.fresh_reg(b1)

        {_, b3} =
          Builder.emit(b2, :int_arith, %{
            dest: dest,
            args: %{kind: :sub_const, lhs: n, value: 1},
            effects: Elmc.Backend.Plan.Types.fallible_effects(dest, [n])
          })

        b3
      end)
      |> Builder.catch_end()
      |> then(fn b ->
        Builder.to_function_plan(Builder.emit_ret(b, 0))
      end)

    assert {:ok, module_map} = Lower.lower(plan)
    wat = Lower.render_wat(module_map)

    assert wat =~ "runtime_as_int"
    assert wat =~ "i32.sub"
    assert wat =~ "runtime_new_int"
    refute wat =~ "f32.sub"
    refute wat =~ "runtime_as_float"
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

  test "boxed Float compare unboxes via as_float and uses f32.eq" do
    # Scene3d countdown loops use `stripIndex == 0` (Float == numeric literal).
    # Pointer i32.eq on handles never terminates — must compare float values.
    plan =
      Builder.new("Test", "float_boxed_compare", args: ["x"], rc_required: false)
      |> then(fn b ->
        {x_reg, b1} = Builder.fresh_reg(b)
        {zero_reg, b2} = Builder.fresh_reg(b1)
        {dest, b3} = Builder.fresh_reg(b2)

        {_, b4} =
          Builder.emit(b3, :load_param, %{
            dest: x_reg,
            args: %{index: 0},
            effects: Elmc.Backend.Plan.Types.empty_effects()
          })

        {_, b5} =
          Builder.emit(b4, :const_int, %{
            dest: zero_reg,
            args: %{value: 0},
            effects: Elmc.Backend.Plan.Types.empty_effects()
          })

        {_, b6} =
          Builder.emit(b5, :compare, %{
            dest: dest,
            args: %{kind: :eq, left: x_reg, right: zero_reg, mode: :float_boxed},
            effects: Elmc.Backend.Plan.Types.empty_effects()
          })

        Builder.to_function_plan(Builder.emit_ret(b6, 0))
      end)

    assert {:ok, module_map} = Lower.lower(plan)
    wat = Lower.render_wat(module_map)

    assert wat =~ "runtime_as_float"
    assert wat =~ "f32.eq"
    assert wat =~ "f32.convert_i32_s"
    refute wat =~ ~r/\(i32\.eq\s+\(local\.get \$reg/
  end

  test "basics_not of string equals passes boxed handle (no new_int of handle id)" do
    # Mimics `Basics.not (item == "")` / filter predicate: string_equals writes a
    # boxed Int, then basics_not must consume that handle — not re-box the ptr.
    plan =
      Builder.new("Test", "string_neq_via_not", args: ["item"], rc_required: false)
      |> then(fn b ->
        {item, b1} = Builder.fresh_reg(b)
        {empty, b2} = Builder.fresh_reg(b1)
        {eq_reg, b3} = Builder.fresh_reg(b2)
        {not_reg, b4} = Builder.fresh_reg(b3)

        {_, b5} =
          Builder.emit(b4, :load_param, %{
            dest: item,
            args: %{index: 0},
            effects: Elmc.Backend.Plan.Types.empty_effects()
          })

        {_, b6} =
          Builder.emit(b5, :const_immortal_string, %{
            dest: empty,
            args: %{value: ""},
            effects: Elmc.Backend.Plan.Types.empty_effects()
          })

        {_, b7} =
          Builder.emit(b6, :compare, %{
            dest: eq_reg,
            args: %{kind: :eq, left: item, right: empty, mode: :string},
            effects: Elmc.Backend.Plan.Types.empty_effects()
          })

        {_, b8} =
          Builder.emit(b7, :call_runtime, %{
            dest: not_reg,
            args: %{builtin: :basics_not, args: [eq_reg]},
            effects: Elmc.Backend.Plan.Types.empty_effects()
          })

        Builder.to_function_plan(Builder.emit_ret(b8, not_reg))
      end)

    assert {:ok, module_map} = Lower.lower(plan)
    wat = Lower.render_wat(module_map)

    assert wat =~ "runtime_string_equals"
    assert wat =~ "runtime_basics_not"
    # Must not insert new_int(handle) between equals and not.
    refute wat =~ ~r/runtime_string_equals[\s\S]*?runtime_new_int[\s\S]*?runtime_basics_not/
  end

  test "call_fn boxes const_int True/False args (no raw i32.const handles)" do
    # Scene3d.cylinder passes True/False as const_int 1/0. Those collide with
    # immortal UNIT on WASM unless boxed before the callee retain.
    callee =
      Builder.new("Scene3d.Entity", "cylinder", args: ["a", "b", "c", "d"], rc_required: false)
      |> then(fn b ->
        {reg, b1} = Builder.get_or_load_param(b, 0, "a")
        Builder.to_function_plan(Builder.emit_ret(b1, reg))
      end)

    caller =
      Builder.new("Scene3d", "cylinder", args: ["m", "c"], rc_required: false)
      |> then(fn b ->
        {m, b1} = Builder.get_or_load_param(b, 0, "m")
        {c, b2} = Builder.get_or_load_param(b1, 1, "c")
        {t, b3} = Builder.emit_const_int(b2, 1)
        {f, b4} = Builder.emit_const_int(b3, 0)
        {dest, b5} = Builder.fresh_reg(b4)

        {_, b6} =
          Builder.emit(b5, :call_fn, %{
            dest: dest,
            args: %{module: "Scene3d.Entity", name: "cylinder", args: [t, f, m, c]},
            effects: Elmc.Backend.Plan.Types.fallible_effects(dest, [t, f, m, c])
          })

        Builder.to_function_plan(Builder.emit_ret(b6, dest))
      end)

    assert {:ok, module_map} = Lower.lower_many([callee, caller])
    wat = Lower.render_wat(module_map)

    assert wat =~ "elmc_fn_Scene3d_cylinder"
    assert wat =~ ~s|(import "runtime" "new_int" (func $runtime_new_int|
    assert wat =~ "runtime_new_int"
    # Must not pass bare i32.const 0/1 as Entity.cylinder args.
    refute wat =~ ~r/call \$elmc_fn_Scene3d_Entity_cylinder \(local\.get \$reg\d+\) \(local\.get \$reg\d+\)/
    assert wat =~ ~r/runtime_new_int[\s\S]*?call \$elmc_fn_Scene3d_Entity_cylinder/
  end

  test "tuple2 of const_int imports runtime.new_int for boxing" do
    # Web Browser.application / Msg constructors build (tag, payload) with
    # const_int tags. Lowering boxes the tag via runtime.new_int before tuple2.
    plan =
      Builder.new("Test", "tagged", args: ["payload"], rc_required: true)
      |> Builder.catch_begin()
      |> then(fn b ->
        {tag, b1} = Builder.emit_const_int(b, 2)
        {payload, b2} = Builder.get_or_load_param(b1, 0, "payload")
        {dest, b3} = Builder.fresh_reg(b2)

        {_, b4} =
          Builder.emit(b3, :call_runtime, %{
            dest: dest,
            args: %{builtin: :tuple2, args: [tag, payload]},
            effects: Elmc.Backend.Plan.Types.fallible_effects(dest, [tag, payload])
          })

        b4
      end)
      |> Builder.catch_end()
      |> then(fn b ->
        Builder.to_function_plan(Builder.emit_ret(b, 0))
      end)

    assert {:ok, module_map} = Lower.lower(plan)
    wat = Lower.render_wat(module_map)

    assert wat =~ ~s|(import "runtime" "new_int" (func $runtime_new_int|
    assert wat =~ ~s|(import "runtime" "tuple2"|
    assert wat =~ ~r/call \$runtime_new_int[\s\S]*?call \$runtime_tuple2/
  end
end
