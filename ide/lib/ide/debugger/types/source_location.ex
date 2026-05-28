defmodule Ide.Debugger.Types.SourceLocation do
  @moduledoc """
  Source span attached to parser-derived view tree nodes.
  """

  @type t :: %{
          optional(:path) => String.t() | nil,
          optional(:line) => non_neg_integer(),
          optional(:call) => String.t(),
          optional(String.t()) => String.t() | integer() | nil
        }

  @type wire_map :: t() | map()
end
