defmodule ElmExecutor.Runtime.SemanticExecutor.Types.CommandMap do
  @moduledoc false

  alias ElmExecutor.Runtime.CoreIREvaluator.Types, as: EvalTypes
  alias ElmExecutor.Runtime.SemanticExecutor.Types, as: SemTypes

  @type kind :: String.t()

  alias ElmExecutor.Runtime.SemanticExecutor.Types, as: SemTypes

  @type t :: %{
          optional(:kind) => kind(),
          optional(:commands) => [t()],
          optional(:package) => String.t(),
          optional(:message) => EvalTypes.runtime_value() | String.t() | map(),
          optional(String.t()) => SemTypes.wire_input(),
          optional(atom()) => SemTypes.wire_input()
        }
end
