defmodule ElmExecutor.Runtime.CoreIREvaluator.Types.ConstructorTagEntry do
  @moduledoc false

  alias ElmExecutor.Runtime.CoreIREvaluator.Types, as: EvalTypes

  @type t :: %{
          optional(:module) => String.t(),
          optional(:union) => String.t(),
          optional(:ctor) => String.t(),
          optional(:tag) => pos_integer(),
          optional(:payload_spec) => String.t() | nil,
          optional(:update_module?) => boolean(),
          optional(atom()) => EvalTypes.wire_input()
        }
end
