defmodule Ide.Debugger.Types.StorageValue do
  @moduledoc """
  Companion storage simulator wire values (`storage_values` in simulator settings).
  """

  alias Ide.Debugger.Types

  @type kind :: :string | :int | :bool | :json | String.t()

  @type scalar_value :: String.t() | integer() | boolean()

  @type value :: scalar_value() | map()

  @type t :: %{
          optional(:kind) => kind(),
          optional(:value) => value(),
          optional(atom()) => Types.wire_input(),
          optional(String.t()) => Types.wire_input()
        }

  @type values_map :: %{optional(String.t()) => t() | wire_map()}

  @type wire_map :: t() | map()
end
