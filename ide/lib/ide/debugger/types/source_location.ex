defmodule Ide.Debugger.Types.SourceLocation do
  @moduledoc """
  Source span attached to parser-derived view tree nodes.
  """

  alias Ide.Debugger.Types

  @type t :: %{
          optional(:path) => String.t() | nil,
          optional(:line) => non_neg_integer(),
          optional(:call) => String.t(),
          optional(String.t()) => String.t() | integer() | nil
        }

  @typedoc "JSON-shaped map when atom-key `t/0` is unavailable at the wire boundary."
  @type wire_map :: t() | Types.wire_map()
end
