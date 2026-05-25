defmodule ElmExecutor.Runtime.CoreIREvaluator.Types.RecordAliasIndex do
  @moduledoc false

  @type key :: {String.t(), String.t()}

  @type t :: %{optional(key()) => [String.t()]}
end
