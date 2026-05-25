defmodule ElmExecutor.Runtime.SemanticExecutor.Types.ViewOutputRow do
  @moduledoc false

  @type kind :: String.t()

  @type t :: %{
          optional(:kind) => kind(),
          optional(String.t()) => term(),
          optional(atom()) => term()
        }

  @type view_output :: [t()]
end
