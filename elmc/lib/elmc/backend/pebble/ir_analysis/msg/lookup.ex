defmodule Elmc.Backend.Pebble.IRAnalysis.Msg.Lookup do
  @moduledoc false
  alias Elmc.Types, as: Types


  alias Elmc.Backend.Pebble.Types

  @spec phone_to_watch_target(
          Types.msg_constructor_list(),
          Types.msg_constructor_payload_specs()
        ) :: Types.msg_tag()
  def phone_to_watch_target(msg_constructors, payload_specs) do
    Enum.find_value(msg_constructors, -1, fn {name, tag} ->
      case Map.get(payload_specs, name) do
        "PhoneToWatch" -> tag
        "Companion.Types.PhoneToWatch" -> tag
        _ -> nil
      end
    end)
  end

  @spec constructor_name_for_tag(Types.msg_constructor_list(), non_neg_integer()) ::
          Types.msg_constructor_name() | nil
  def constructor_name_for_tag(constructors, tag) when is_integer(tag) do
    Enum.find_value(constructors, fn
      {name, ^tag} -> name
      _ -> nil
    end)
  end
end
