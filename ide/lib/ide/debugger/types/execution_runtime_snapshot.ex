defmodule Ide.Debugger.Types.ExecutionRuntimeSnapshot do
  @moduledoc """
  Runtime telemetry map on step results (`runtime` / `elm_executor` on `model_patch`).

  Populated by semantic executor, elmc adapter, and `RuntimeExecutor.annotate_execution_backend/3`.
  """

  alias Ide.Debugger.Types
  @type t :: %{
          optional(:engine) => String.t(),
          optional(:source_root) => String.t(),
          optional(:rel_path) => String.t() | nil,
          optional(:execution_backend) => String.t(),
          optional(:runtime_mode) => String.t(),
          optional(:external_fallback_reason) => String.t(),
          optional(:runtime_model_source) => String.t(),
          optional(:operation_source) => String.t(),
          optional(:view_tree_source) => String.t(),
          optional(:heuristic_fallback_used) => boolean(),
          optional(:followup_message_count) => non_neg_integer(),
          optional(:view_output_count) => non_neg_integer(),
          optional(String.t()) => Types.wire_input(),
          optional(atom()) => Types.wire_input()
        }

  @type wire_map :: t() | map()
end
