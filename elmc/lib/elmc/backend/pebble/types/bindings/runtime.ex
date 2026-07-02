defmodule Elmc.Backend.Pebble.Types.Bindings.Runtime do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types.Bindings.Msg
  alias Elmc.Backend.Pebble.Types.Core

  @type event_dispatch_bindings :: %{
          required(:msg) => Msg.msg_fragments(),
          required(:random_generate_tag) => Core.msg_tag(),
          required(:compass_dispatch_source) => Core.c_source()
        }

  @type source_bindings :: %{
          required(:msg) => Msg.msg_fragments(),
          required(:direct_view_macro) => Core.c_macro_name(),
          required(:entry_view_scene_append) => Core.c_symbol(),
          required(:entry_view_fn) => Core.c_symbol(),
          required(:random_generate_tag) => Core.msg_tag(),
          required(:has_view) => boolean(),
          required(:compass_dispatch_source) => Core.c_source(),
          required(:scene_writer_source) => Core.c_source()
        }

  @type scene_build_bindings :: %{
          required(:entry_view_scene_append) => Core.c_symbol(),
          required(:direct_view_macro) => Core.c_macro_name()
        }

  @type view_command_bindings :: %{
          required(:entry_view_fn) => Core.c_symbol(),
          required(:has_view) => boolean(),
          required(:direct_view_macro) => Core.c_macro_name()
        }
end
