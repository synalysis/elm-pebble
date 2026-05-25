defmodule Ide.Debugger.Types.StorageValue do
  @moduledoc """
  Companion storage simulator wire values (`storage_values` in simulator settings).
  """

  @type kind :: :string | :int | :bool | :json | String.t()

  @type t :: %{
          optional(:kind) => kind(),
          optional(:value) => term(),
          optional(atom()) => term(),
          optional(String.t()) => term()
        }

  @type values_map :: %{optional(String.t()) => t() | wire_map()}

  @type wire_map :: t() | map()
end
