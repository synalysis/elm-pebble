defmodule Ide.Debugger.Types.InnerRuntimeModel do
  @moduledoc """
  Nested `runtime_model` map inside debugger app/execution models.
  """

  alias Ide.Debugger.Types

  @type t :: Types.wire_string_map()

  @typedoc "String-key runtime model when typed `wire_string_map/0` is unavailable at the wire boundary."
  @type wire_map :: t() | Types.wire_map()
end
