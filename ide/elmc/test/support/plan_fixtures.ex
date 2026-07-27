defmodule Elmc.PlanFixtures do
  @moduledoc false

  alias Elmc.Backend.Plan.{Builder, Types}

  def companion_send_plan do
    b =
      Builder.new("Companion.Watch", "sendWatchToPhone",
        args: ["message"],
        rc_required: true,
        fallible: true
      )

    b = Builder.catch_begin(b)
    {msg, b0} = Builder.emit_load_param(b, 0)
    {tag, b1} = Builder.fresh_reg(b0)
    {val, b2} = Builder.fresh_reg(b1)

    {_, b3} =
      Builder.emit(b2, :call_fn, %{
        dest: tag,
        args: %{module: "Companion.Internal", name: "watchToPhoneTag", args: [msg]},
        effects: Types.fallible_effects(tag, [msg])
      })

    {_, b4} =
      Builder.emit(b3, :call_fn, %{
        dest: val,
        args: %{module: "Companion.Internal", name: "watchToPhoneValue", args: [msg]},
        effects: Types.fallible_effects(val, [msg])
      })

    {_, b5} =
      Builder.emit(b4, :pebble_cmd, %{
        dest: :fn_out,
        args: %{builtin: :cmd2, kind: %{c_expr: "ELMC_PEBBLE_CMD_COMPANION_SEND"}, params: [tag, val]},
        effects: Types.fallible_transfer([tag, val], [tag, val])
      })

    {_, b6} =
      Builder.emit(b5, :publish, %{
        dest: :fn_out,
        args: %{},
        effects: Types.empty_effects()
      })

    b7 = Builder.catch_end(b6)
    b8 = Builder.emit_ret(b7, :fn_out)
    Builder.to_function_plan(b8)
  end
end
