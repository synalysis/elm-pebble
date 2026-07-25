defmodule Elmc.PlanCallCoerceScratchDestTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.Lower.Function
  alias Elmc.Backend.Wasm.Lower

  test "Int literal coerce at function tail uses distinct scratch regs, not fn_out" do
    # HeroScene.elmCyan = Color.rgb255 96 181 204. Native-int ABI keeps const_int
    # immediates (CallCoerce skips boxing); WASM boxes them at call_fn into
    # distinct temps. If any plan-level new_int still targets :fn_out, WASM
    # would pass (fn_out, fn_out, fn_out) and materials become grayscale.
    decl = %{
      name: "elmCyan",
      args: [],
      type: "Color.Color",
      expr: %{
        op: :qualified_call,
        target: "Color.rgb255",
        args: [
          %{op: :int_literal, value: 96},
          %{op: :int_literal, value: 181},
          %{op: :int_literal, value: 204}
        ]
      }
    }

    # Body mirrors avh4/elm-color: each Int arg is used via scaleFrom255 so
    # NativeFunctionCall.arg_kinds is [:native_int, :native_int, :native_int].
    scale = %{
      name: "scaleFrom255",
      args: ["c"],
      type: "Int -> Float",
      expr: %{
        op: :binop,
        operator: "/",
        left: %{op: :qualified_call, target: "Basics.toFloat", args: [%{op: :var, name: "c"}]},
        right: %{op: :int_literal, value: 255}
      }
    }

    rgb255 = %{
      name: "rgb255",
      args: ["r", "g", "b"],
      type: "Int -> Int -> Int -> Color.Color",
      expr: %{
        op: :constructor_call,
        target: "RgbaSpace",
        args: [
          %{op: :qualified_call, target: "Color.scaleFrom255", args: [%{op: :var, name: "r"}]},
          %{op: :qualified_call, target: "Color.scaleFrom255", args: [%{op: :var, name: "g"}]},
          %{op: :qualified_call, target: "Color.scaleFrom255", args: [%{op: :var, name: "b"}]},
          %{op: :float_literal, value: 1.0}
        ]
      }
    }

    decl_map = %{
      {"Main", "elmCyan"} => decl,
      {"Color", "rgb255"} => rgb255,
      {"Color", "scaleFrom255"} => scale
    }

    assert {:ok, plan} = Function.lower(decl, "Main", decl_map, rc_required: true)

    int_news =
      for block <- plan.blocks,
          %{op: :call_runtime, dest: dest, args: %{builtin: :new_int}} = instr <- block.instrs,
          do: {dest, instr}

    # Native-int ABI: prefer const_int immediates (no plan-level new_int). Any
    # remaining boxes must still use distinct scratch regs, never fn_out.
    dests = Enum.map(int_news, fn {dest, _} -> dest end)
    refute Enum.any?(dests, &(&1 in [:fn_out, :branch_out])),
           "coerced Int args must be scratch regs; got #{inspect(dests)}"

    assert length(Enum.uniq(dests)) == length(dests),
           "each coerced Int must get its own reg; got #{inspect(dests)}"

    call =
      Enum.find_value(plan.blocks, fn block ->
        Enum.find(block.instrs, fn
          %{op: :call_fn, args: %{module: "Color", name: "rgb255"}} -> true
          _ -> false
        end)
      end)

    assert call
    arg_regs = call.args.args
    assert length(arg_regs) == 3
    assert Enum.all?(arg_regs, &is_integer/1)
    assert length(Enum.uniq(arg_regs)) == 3
    refute Enum.any?(arg_regs, &(&1 in [:fn_out, :branch_out]))

    assert {:ok, module_map} = Lower.lower(plan)
    wat = Lower.render_wat(module_map)

    refute wat =~
             ~r/Color_rgb255 \(local\.get \$fn_out\) \(local\.get \$fn_out\) \(local\.get \$fn_out\)/,
           "WASM must not pass fn_out thrice to Color.rgb255"
  end

  test "Float literal coerce at function tail uses distinct scratch regs for vec3" do
    decl = %{
      name: "zeroVec3",
      args: [],
      type: "Math.Vector3.Vector3",
      expr: %{
        op: :qualified_call,
        target: "Math.Vector3.vec3",
        args: [
          %{op: :int_literal, value: 0},
          %{op: :int_literal, value: 0},
          %{op: :int_literal, value: 0}
        ]
      }
    }

    decl_map = %{
      {"Main", "zeroVec3"} => decl,
      {"Math.Vector3", "vec3"} => %{
        name: "vec3",
        args: ["x", "y", "z"],
        type: "Float -> Float -> Float -> Math.Vector3.Vector3",
        expr: %{op: :var, name: "x"}
      }
    }

    assert {:ok, plan} = Function.lower(decl, "Main", decl_map, rc_required: true)

    float_news =
      for block <- plan.blocks,
          %{op: :call_runtime, dest: dest, args: %{builtin: :new_float}} <- block.instrs,
          do: dest

    assert length(float_news) >= 3
    refute Enum.any?(float_news, &(&1 in [:fn_out, :branch_out]))
    assert length(Enum.uniq(float_news)) == length(float_news)

    assert {:ok, module_map} = Lower.lower(plan)
    wat = Lower.render_wat(module_map)

    refute wat =~
             ~r/Vector3_vec3 \(local\.get \$fn_out\) \(local\.get \$fn_out\) \(local\.get \$fn_out\)/
  end
end
