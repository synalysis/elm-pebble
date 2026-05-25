defmodule ElmExecutor.Runtime.SemanticExecutor.Types.ExecutionResult do
  @moduledoc """
  Successful return map from `SemanticExecutor.execute/1` (debugger runtime executor contract).
  """

  alias ElmExecutor.Runtime.SemanticExecutor.Types.ViewOutputRow
  alias ElmExecutor.Runtime.SemanticExecutor.Types.ViewTreeNode

  @type runtime_snapshot :: %{optional(String.t()) => term(), optional(atom()) => term()}

  @type model_patch :: %{optional(String.t()) => term(), optional(atom()) => term()}

  @type protocol_event :: %{
          optional(:type) => String.t(),
          optional(:payload) => map(),
          optional(atom()) => term(),
          optional(String.t()) => term()
        }

  @type followup_message :: %{optional(String.t()) => term(), optional(atom()) => term()}

  @type t :: %{
          optional(:model_patch) => model_patch(),
          optional(:view_tree) => ViewTreeNode.view_tree() | ViewTreeNode.t() | nil,
          optional(:view_output) => ViewOutputRow.view_output(),
          optional(:runtime) => runtime_snapshot(),
          optional(:protocol_events) => [protocol_event()],
          optional(:followup_messages) => [followup_message()],
          optional(atom()) => term(),
          optional(String.t()) => term()
        }

  @type wire_map :: t() | map()
end
