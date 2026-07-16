defmodule Elmc.WasmRecordUpdateOwnedTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.Builder
  alias Elmc.Backend.Wasm.Lower

  test "record_update nulls base owned after cow_drop" do
    plan =
      Builder.new("Test", "update_field", args: ["base"], rc_required: true)
      |> Builder.catch_begin()
      |> then(fn b ->
        {base, b1} = Builder.emit_load_param(b, 0)
        {val, b2} = Builder.fresh_reg(b1)

        {_, b3} =
          Builder.emit(b2, :call_runtime, %{
            dest: val,
            args: %{builtin: :new_int, args: [], literal: 9},
            effects: Elmc.Backend.Plan.Types.fallible_effects(val)
          })

        {dest, b4} = Builder.fresh_reg(b3)

        {_, b5} =
          Builder.emit(b4, :record_update, %{
            dest: dest,
            args: %{base: base, value: val, field_index: 0},
            effects: %{
              produces: {:owned, dest},
              consumes: [val],
              borrows: [base],
              fallible: false
            }
          })

        b5
      end)
      |> Builder.catch_end()
      |> then(fn b ->
        Builder.to_function_plan(Builder.emit_ret(b, 2))
      end)

    assert {:ok, module_map} = Lower.lower(plan)
    wat = Lower.render_wat(module_map)

    assert wat =~ "runtime_record_update"
    # Dest/value/base owned shadows cleared (publish + cow_drop / consume).
    assert wat =~ ~r/local\.set \$owned\d+ \(i32\.const 0\)/
  end
end
