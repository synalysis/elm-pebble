defmodule ElmExecutor.Runtime.SemanticExecutor.Types.CommandMap do
  @moduledoc false

  @type kind :: String.t()

  @type t :: %{
          optional(:kind) => kind(),
          optional(:commands) => [t()],
          optional(:package) => String.t(),
          optional(:message) => term(),
          optional(String.t()) => term(),
          optional(atom()) => term()
        }
end
