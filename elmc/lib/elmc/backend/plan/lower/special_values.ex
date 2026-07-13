defmodule Elmc.Backend.Plan.Lower.SpecialValues do
  @moduledoc """
  Plan-primary entry for qualified-call / runtime rewrite tables.

  Rewrites still live in `Elmc.Backend.CCodegen.SpecialValues` until each
  handler is migrated to plan builtins or platform lowerers.
  """

  alias Elmc.Backend.Plan.Types

  @spec special_value_from_target(String.t(), Types.special_value_args()) ::
          Types.special_value_expr()
  defdelegate special_value_from_target(target, args),
    to: Elmc.Backend.CCodegen.SpecialValues

  @spec command_kind_expr(atom()) :: String.t()
  defdelegate command_kind_expr(kind), to: Elmc.Backend.CCodegen.SpecialValues.Helpers
end
