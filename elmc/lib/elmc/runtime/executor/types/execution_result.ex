defmodule Elmc.Runtime.Executor.Types.ExecutionResult do
  @moduledoc """
  Successful return map from `Elmc.Runtime.Executor.execute/1`.
  """

  @type model_patch :: map()
  @type runtime_snapshot :: map()

  @type t :: %{
          required(:model_patch) => model_patch(),
          required(:view_output) => [map()],
          required(:runtime) => runtime_snapshot(),
          required(:protocol_events) => [map()],
          required(:followup_messages) => [map() | String.t()],
          optional(:view_tree) => map() | nil,
          optional(atom()) => term(),
          optional(String.t()) => term()
        }

  @type wire_map :: t() | map()
end
