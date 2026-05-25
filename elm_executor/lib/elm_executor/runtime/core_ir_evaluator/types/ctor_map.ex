defmodule ElmExecutor.Runtime.CoreIREvaluator.Types.CtorMap do
  @moduledoc false

  @type t :: %{
          optional(:ctor) => String.t(),
          optional(:args) => list(),
          optional(String.t()) => term(),
          optional(atom()) => term()
        }
end
