defmodule ElmExecutor.Runtime.SemanticExecutor.Types.ExecutionResult do
  @moduledoc """
  Successful return map from `SemanticExecutor.execute/1` (debugger runtime executor contract).
  """

  alias ElmExecutor.Runtime.CoreIREvaluator.Types, as: EvalTypes
  alias ElmExecutor.Runtime.SemanticExecutor.Types, as: SemTypes
  alias ElmExecutor.Runtime.SemanticExecutor.Types.ViewOutputRow
  alias ElmExecutor.Runtime.SemanticExecutor.Types.ViewTreeNode

  @type runtime_snapshot :: SemTypes.wire_map()

  @type model_patch :: SemTypes.wire_map()

  @type protocol_event :: %{
          optional(:type) => String.t(),
          optional(:payload) => map(),
          optional(atom()) => SemTypes.wire_input(),
          optional(String.t()) => SemTypes.wire_input()
        }

  @type followup_message :: SemTypes.wire_map() | String.t() | EvalTypes.runtime_value()

  @type t :: %{
          optional(:model_patch) => model_patch(),
          optional(:view_tree) => ViewTreeNode.view_tree() | ViewTreeNode.t() | nil,
          optional(:view_output) => ViewOutputRow.view_output(),
          optional(:runtime) => runtime_snapshot(),
          optional(:protocol_events) => [protocol_event()],
          optional(:followup_messages) => [followup_message()],
          optional(atom()) => SemTypes.wire_input(),
          optional(String.t()) => SemTypes.wire_input()
        }

  @type wire_map :: t() | map()
end
