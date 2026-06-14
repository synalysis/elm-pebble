defmodule Elmc.Backend.Pebble.FeatureFlags.EventFlags.Lookup do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec has_any_constructor?(Types.msg_constructor_list(), [Types.msg_constructor_name()]) ::
          boolean()
  def has_any_constructor?(msg_constructors, names) do
    Enum.any?(msg_constructors, fn {name, _tag} -> name in names end)
  end
end
