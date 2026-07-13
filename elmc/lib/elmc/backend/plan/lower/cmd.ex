defmodule Elmc.Backend.Plan.Lower.Cmd do
  @moduledoc false

  alias Elmc.Backend.Plan.Types
  alias Elmc.Backend.Plan.Lower.Platform.Pebble
  alias Elmc.Backend.Plan.{Builder, Context}

  @spec compile(Types.ir_expr(), Context.t(), Builder.t()) ::
          Types.compile_result_required()
  def compile(expr, ctx, b), do: Pebble.compile_cmd(expr, ctx, b)
end
