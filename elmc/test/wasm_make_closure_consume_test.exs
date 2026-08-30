defmodule Elmc.WasmMakeClosureConsumeTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.{Builder, Types}
  alias Elmc.Backend.Wasm.Lower

  test "make_closure consumes named-local captures so owned is nulled" do
    plan =
      Builder.new("Test", "pack", args: ["rec"], rc_required: true)
      |> Builder.catch_begin()
      |> then(fn b ->
        {base, b1} = Builder.emit_load_param(b, 0)

        {field, b2} = Builder.fresh_reg(b1)

        {_, b3} =
          Builder.emit(b2, :record_get, %{
            dest: field,
            args: %{base: base, field_index: 0},
            effects: %{
              produces: {:owned, field},
              consumes: [],
              borrows: [base],
              fallible: false
            }
          })

        b4 = %{b3 | locals: Map.put(b3.locals || %{}, "field", field)}
        {capture, b5} = Builder.dup_all_regs_for_consume(b4, [field])
        {dest, b6} = Builder.fresh_reg(b5)

        {_, b7} =
          Builder.emit(b6, :make_closure, %{
            dest: dest,
            args: %{index: 0, arity: 1, captures: capture},
            effects: %{
              produces: {:owned, dest},
              consumes: capture,
              borrows: [],
              fallible: true
            }
          })

        b8 = Builder.emit_publish_fn_out(b7, dest)
        Builder.catch_end(b8)
      end)
      |> then(fn b ->
        plan = Builder.to_function_plan(Builder.emit_ret(b, :fn_out))
        %{plan | lambdas: [dummy_lambda()]}
      end)

    closure_instr =
      plan.blocks
      |> Enum.flat_map(& &1.instrs)
      |> Enum.find(fn
        %{op: :make_closure} -> true
        _ -> false
      end)

    assert closure_instr
    assert match?(%{effects: %{consumes: [_ | _]}}, closure_instr)

    assert {:ok, module_map} = Lower.lower(plan)
    wat = Lower.render_wat(module_map)

    assert wat =~ "make_closure"
    assert wat =~ "runtime_record_get"
    assert wat =~ ~r/local\.set \$owned\d+ \(i32\.const 0\)/
  end

  defp dummy_lambda do
    %Types.FunctionPlan{
      module: "Test",
      name: "pack_lambda_0",
      params: [],
      blocks: [
        %Types.Block{id: 0, instrs: [], terminator: {:ret, :fn_out}}
      ],
      entry_block: 0,
      lambdas: [],
      rc_required: true,
      fallible: true,
      lambda_arg_count: 1,
      reg_count: 0
    }
  end
end
