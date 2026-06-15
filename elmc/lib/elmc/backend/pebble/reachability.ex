defmodule Elmc.Backend.Pebble.Reachability do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Types, as: CCodegenTypes
  alias Elmc.Backend.Pebble.{Reachability.Collector, Reachability.Walker, Types}

  @spec reachable_call_targets(ElmEx.IR.t(), Types.entry_module()) :: Types.call_target_set()
  defdelegate reachable_call_targets(ir, entry_module), to: Walker

  @spec collect_targets(CCodegenTypes.ir_expr() | list() | nil | String.t() | number() | atom()) ::
          Types.call_target_list()
  defdelegate collect_targets(expr), to: Collector, as: :collect
end
