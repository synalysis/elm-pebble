defmodule Ide.Debugger.Protocol.ConstructorValue do
  @moduledoc """
  Elm custom-type constructor value on the companion protocol wire (ctor + args).
  """

  alias Ide.Debugger.Types

  @type t :: %{
          optional(:ctor) => String.t(),
          optional(:args) => [Types.protocol_wire_arg()],
          optional(String.t()) => Types.wire_input()
        }

  @type wire_value :: t() | Types.wire_map()
end
