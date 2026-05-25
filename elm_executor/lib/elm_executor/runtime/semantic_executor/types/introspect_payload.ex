defmodule ElmExecutor.Runtime.SemanticExecutor.Types.IntrospectPayload do
  @moduledoc """
  Subset of IDE `elm_introspect` fields consumed by `SemanticExecutor` (string keys at runtime).

  Mirrors `Ide.Debugger.ElmIntrospect.Payload` without a compile-time dependency on `ide`.
  """

  alias ElmExecutor.Runtime.CoreIREvaluator.Types, as: EvalTypes
  alias ElmExecutor.Runtime.SemanticExecutor.Types, as: SemTypes
  alias ElmExecutor.Runtime.SemanticExecutor.Types.ViewTreeNode

  @type cmd_op_row :: SemTypes.wire_map()
  @type view_source_locations :: %{optional(String.t()) => [map()] | map()}

  @type t :: %{
          optional(:module) => String.t(),
          optional(:init_model) => EvalTypes.runtime_value(),
          optional(:view_tree) => ViewTreeNode.view_tree() | map(),
          optional(:view_source_locations) => view_source_locations(),
          optional(:msg_constructors) => [String.t()],
          optional(:update_case_branches) => [String.t()],
          optional(:view_case_branches) => [String.t()],
          optional(:init_cmd_calls) => [cmd_op_row()],
          optional(String.t()) => SemTypes.wire_input(),
          optional(atom()) => SemTypes.wire_input()
        }

  @type wire_payload :: t() | SemTypes.wire_map()
end
