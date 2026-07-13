defmodule Elmc.Backend.Wasm.Lower do
  @moduledoc """
  Placeholder for future Plan → WASM lowering (web Elm).

  Not implemented in this project. See `plan/README.md`.
  """

  alias Elmc.Backend.Plan.Types.FunctionPlan

  @spec lower(FunctionPlan.t()) :: {:error, :not_implemented}
  def lower(_plan), do: {:error, :not_implemented}
end
