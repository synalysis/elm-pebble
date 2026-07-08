defmodule Elmc.Backend.Plan.Lower.Cmd do
  @moduledoc false

  alias Elmc.Backend.Plan.Lower.Platform.Pebble
  alias Elmc.Backend.Plan.{Builder, Context}

  @spec compile(map(), Context.t(), Builder.t()) ::
          {:ok, term(), Builder.t()} | :unsupported
  def compile(expr, ctx, b), do: Pebble.compile_cmd(expr, ctx, b)
end
