defmodule Ide.Debugger.Types.StorageValue do
  @moduledoc """
  Companion storage simulator wire values (`storage_values` in simulator settings).
  """

  alias Ide.Debugger.Types

  @type kind :: :string | :int | :bool | :json | String.t()

  @type scalar_value :: String.t() | integer() | boolean()

  @type value :: scalar_value() | Types.wire_string_map()

  @type t :: %{
          optional(:kind) => kind(),
          optional(:value) => value(),
          optional(String.t()) => Types.wire_input()
        }

  @type values_map :: %{optional(String.t()) => t() | Types.wire_string_map()}

  @typedoc "JSON-shaped map when atom-key `t/0` is unavailable at the wire boundary."
  @type wire_map :: t() | Types.wire_map()
end
