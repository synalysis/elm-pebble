defmodule Elmc.Backend.CCodegen.DirectRender.Emit.Operand do
  @moduledoc """
  DirectRender-owned IR→C operand emitter.

  Single production entry for nested Elm expressions in view/scene command
  streams. Uses explicit `ValueSlots.transfer/1` at ownership-transfer call
  sites instead of post-hoc C-text heuristics.
  """
  alias Elmc.Backend.CCodegen.Types, as: Types

  alias Elmc.Backend.CCodegen.DirectRender.Emit.ExprDispatch
  alias Elmc.Backend.CCodegen.ValueSlots

  @take_call ~r/\b(elmc_(?:tuple2|list_cons|list_from_values|record_new(?:_static|_values)?|cmd_batch))(?:_take)?\s*\([^;]*\b([A-Za-z_][A-Za-z0-9_]*)\b/

  @spec compile(Types.ir_expr() | nil, Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  def compile(expr, env, counter) do
    env =
      env
      |> Map.put_new(:__direct_render_emit__, true)
      |> Map.put(:__operand_take_marking__, true)

    {code, var, next} = ExprDispatch.compile(expr, env, counter)
    {code, var, next} = maybe_mark_take_transfers(code, var, next)
    {code, var, next}
  end

  @spec maybe_mark_take_transfers(String.t(), String.t(), Types.compile_counter()) ::
          Types.compile_result()
  defp maybe_mark_take_transfers(code, var, counter) when is_binary(code) do
    Regex.scan(@take_call, code)
    |> Enum.map(fn [_full, _fn, arg] -> arg end)
    |> Enum.uniq()
    |> Enum.each(&ValueSlots.transfer/1)

    {code, var, counter}
  end
end
