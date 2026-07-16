defmodule Elmc.WasmListConsumeProjTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.Backend.Plan.Lower.Expr
  alias Elmc.Backend.Wasm.Lower

  test "list_cons consumes named-local head so owned is released/nulled" do
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

        {tail, b5} = Builder.fresh_reg(b4)

        {_, b6} =
          Builder.emit(b5, :call_runtime, %{
            dest: tail,
            args: %{builtin: :list_nil, args: []},
            effects: Elmc.Backend.Plan.Types.fallible_effects(tail)
          })

        ctx = Context.new(rc_required: true, fallible: true, module: "Test")

        case Expr.compile_runtime_builtin(:list_cons, [field, tail], ctx, b6) do
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

    cons_instr =
      plan.blocks
      |> Enum.flat_map(& &1.instrs)
      |> Enum.find(fn
        %{op: :call_runtime, args: %{builtin: :list_cons}} -> true
        _ -> false
      end)

    assert cons_instr
    assert match?(%{effects: %{consumes: [_ | _]}}, cons_instr)

    assert {:ok, module_map} = Lower.lower(plan)
    wat = Lower.render_wat(module_map)

    assert wat =~ "list_cons"
    assert wat =~ "runtime_record_get"
    # After consume, owned shadow for the named-local head must be cleared.
    assert wat =~ ~r/local\.set \$owned\d+ \(i32\.const 0\)/
  end
end
