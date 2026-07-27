defmodule Elmc.PlanScaleFrom255Test do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.Lower.Function
  alias Elmc.Backend.Wasm.Lower

  test "toFloat c / 255 at function tail keeps distinct fdiv operands" do
    # Color.scaleFrom255 c = toFloat c / 255. When both operands compile into
    # fn_out at the function tail, WASM does as_float(fn_out)/as_float(fn_out)
    # → every rgb255 channel becomes 1.0 (pure white materials).
    decl = %{
      name: "scaleFrom255",
      args: ["c"],
      type: "Int -> Float",
      expr: %{
        op: :call,
        name: "__fdiv__",
        args: [
          %{op: :call, name: "Basics.toFloat", args: [%{op: :var, name: "c"}]},
          %{op: :int_literal, value: 255}
        ]
      }
    }

    decl_map = %{{"Color", "scaleFrom255"} => decl}

    assert {:ok, plan} =
             Function.lower(decl, "Color", decl_map, rc_required: true)

    assert {:ok, module_map} = Lower.lower(plan)
    wat = Lower.render_wat(module_map)

    assert wat =~ "runtime_float_div_bits"
    assert wat =~ "runtime_basics_to_float"

    # Distinct operands: toFloat result in a scratch reg, 255 in another slot —
    # not as_float(fn_out)/as_float(fn_out) which forced every channel to 1.0.
    assert wat =~ ~r/as_float \(local\.get \$reg\d+\)/
    refute wat =~
             ~r/float_div_bits \(call \$runtime_as_float \(local\.get \$fn_out\)\) \(call \$runtime_as_float \(local\.get \$fn_out\)\)/
  end
end
