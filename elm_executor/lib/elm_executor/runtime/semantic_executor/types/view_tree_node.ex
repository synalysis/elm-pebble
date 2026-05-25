defmodule ElmExecutor.Runtime.SemanticExecutor.Types.ViewTreeNode do
  @moduledoc false

  alias ElmExecutor.Runtime.CoreIREvaluator.Types, as: EvalTypes
  alias ElmExecutor.Runtime.SemanticExecutor.Types, as: SemTypes

  @type node_type :: String.t()

  @type t :: %{
          optional(:type) => node_type(),
          optional(:label) => String.t(),
          optional(:children) => [t() | map()],
          optional(:value) => EvalTypes.runtime_value(),
          optional(:op) => String.t(),
          optional(String.t()) => SemTypes.wire_input(),
          optional(atom()) => SemTypes.wire_input()
        }

  @type view_tree :: t() | %{String.t() => t() | map()}
end
