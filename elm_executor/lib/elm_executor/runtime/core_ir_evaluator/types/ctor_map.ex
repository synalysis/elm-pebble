defmodule ElmExecutor.Runtime.CoreIREvaluator.Types.CtorMap do
  @moduledoc false

  alias ElmExecutor.Runtime.CoreIREvaluator.Types, as: EvalTypes

  @type t :: %{
          optional(:ctor) => String.t(),
          optional(:args) => [EvalTypes.runtime_value()],
          optional(String.t()) => EvalTypes.wire_input(),
          optional(atom()) => EvalTypes.wire_input()
        }
end
