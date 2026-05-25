defmodule ElmExecutor.Runtime.SemanticExecutor.Types.ExecutionRequest do
  @moduledoc false

  alias ElmExecutor.Runtime.CoreIREvaluator.Types, as: EvalTypes
  alias ElmExecutor.Runtime.SemanticExecutor.Types.{EvalContext, IntrospectPayload}

  @type introspect :: IntrospectPayload.wire_payload()
  @type runtime_model :: %{optional(String.t()) => term(), optional(atom()) => term()}
  @type view_tree :: map()

  @type t :: %{
          optional(:source_root) => String.t(),
          optional(:rel_path) => String.t() | nil,
          optional(:source) => String.t(),
          optional(:introspect) => introspect(),
          optional(:current_model) => runtime_model(),
          optional(:current_view_tree) => view_tree(),
          optional(:message) => String.t() | nil,
          optional(:message_value) => EvalTypes.runtime_value() | map() | nil,
          optional(:update_branches) => [String.t()] | nil,
          optional(:elm_executor_core_ir) => EvalTypes.core_ir(),
          optional(:elm_executor_metadata) => map(),
          optional(:vector_resource_indices) => EvalContext.resource_indices(),
          optional(:bitmap_resource_indices) => EvalContext.resource_indices(),
          optional(String.t()) => term(),
          optional(atom()) => term()
        }
end
