defmodule Ide.Debugger.Types.InnerRuntimeModel do
  @moduledoc """
  Nested `runtime_model` map inside debugger app/execution models.
  """

  alias Ide.Debugger.Types

  @type t :: Types.wire_map()

  @type wire_map :: t() | Types.wire_map()
end
