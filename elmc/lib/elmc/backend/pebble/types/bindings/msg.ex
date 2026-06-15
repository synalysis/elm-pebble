defmodule Elmc.Backend.Pebble.Types.Bindings.Msg do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types.Core

  @type msg_fragments :: %{
          required(:value_decode_cases) => Core.c_source(),
          required(:key_decode_cases) => Core.c_source(),
          required(:msg_constructor_arity_cases) => Core.c_source(),
          required(:tick_has_payload?) => boolean(),
          required(:current_second_helper) => Core.c_source(),
          required(:storage_string_tag) => Core.msg_tag(),
          required(:msg_constructor_arity_fn) => Core.c_source()
        }

  @type app_lifecycle_bindings :: %{
          required(:msg) => msg_fragments()
        }
end
