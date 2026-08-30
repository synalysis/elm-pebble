defmodule Elmc.WasmCmdMapConsumeTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.Backend.Plan.Lower.Expr
  alias Elmc.Backend.Wasm.Lower

  test "cmd_map consumes named-local operands so owned is nulled" do
    {plan, instr} = transfer_builtin_plan(:cmd_map)
    assert match?(%{effects: %{consumes: [_ | _]}}, instr)

    assert {:ok, module_map} = Lower.lower(plan)
    wat = Lower.render_wat(module_map)

    assert wat =~ "cmd_map"
    assert wat =~ "runtime_record_get"
    assert wat =~ ~r/local\.set \$owned\d+ \(i32\.const 0\)/
    refute wat =~ ~r/call \$runtime\.release/
  end

  test "sub_map consumes named-local operands so owned is nulled" do
    {plan, instr} = transfer_builtin_plan(:sub_map)
    assert match?(%{effects: %{consumes: [_ | _]}}, instr)

    assert {:ok, module_map} = Lower.lower(plan)
    wat = Lower.render_wat(module_map)

    assert wat =~ "sub_map"
    assert wat =~ ~r/local\.set \$owned\d+ \(i32\.const 0\)/
    refute wat =~ ~r/call \$runtime\.release/
  end

  defp transfer_builtin_plan(builtin) do
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

        {other, b5} = Builder.fresh_reg(b4)

        {_, b6} =
          Builder.emit(b5, :call_runtime, %{
            dest: other,
            args: %{builtin: :new_int, args: [], literal: 1},
            effects: Elmc.Backend.Plan.Types.fallible_effects(other)
          })

        ctx = Context.new(rc_required: true, fallible: true, module: "Test")

        case Expr.compile_runtime_builtin(builtin, [field, other], ctx, b6) do
          {:ok, dest, b7} when is_integer(dest) ->
            b8 = Builder.emit_publish_fn_out(b7, dest)
            Builder.catch_end(b8)

          other ->
            flunk("unexpected compile_runtime_builtin: #{inspect(other)}")
        end
      end)
      |> then(fn b ->
        Builder.to_function_plan(Builder.emit_ret(b, :fn_out))
      end)

    instr =
      plan.blocks
      |> Enum.flat_map(& &1.instrs)
      |> Enum.find(fn
        %{op: :call_runtime, args: %{builtin: ^builtin}} -> true
        _ -> false
      end)

    {plan, instr}
  end
end
