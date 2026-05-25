defmodule Ide.Debugger.Protocol.ConstructorValue do
  @moduledoc """
  Elm custom-type constructor value on the companion protocol wire (ctor + args).
  """

  @type t :: %{
          optional(:ctor) => String.t(),
          optional(:args) => [term()],
          optional(String.t()) => term(),
          optional(atom()) => term()
        }

  @type wire_value :: t() | %{optional(String.t()) => term(), optional(atom()) => term()}
end
