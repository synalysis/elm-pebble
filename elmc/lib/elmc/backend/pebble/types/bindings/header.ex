defmodule Elmc.Backend.Pebble.Types.Bindings.Header do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types.Core

  @type header_msg_macros :: %{
          required(:enum_members) => Core.c_source(),
          required(:presence_macros) => Core.c_source()
        }

  @type header_bindings :: %{
          required(:scene_writer_early) => Core.c_source(),
          required(:feature_macros) => Core.c_source(),
          required(:run_mode_enum) => Core.c_source(),
          required(:msg_enum_members) => Core.c_source(),
          required(:msg_presence_macros) => Core.c_source(),
          required(:button_id_enum) => Core.c_source(),
          required(:button_event_macros) => Core.c_source(),
          required(:accel_axis_enum) => Core.c_source(),
          required(:draw_kind_enum) => Core.c_source(),
          required(:command_kind_enum) => Core.c_source(),
          required(:ui_node_kind_enum) => Core.c_source(),
          required(:scene_writer_late) => Core.c_source(),
          required(:entry_view_scene_append) => Core.c_symbol(),
          required(:phone_to_watch_target) => Core.msg_tag(),
          required(:watch_model_macros) => Core.c_source(),
          required(:watch_color_macros) => Core.c_source(),
          required(:accel_samples_per_update) => pos_integer(),
          required(:accel_sampling_hz) => pos_integer()
        }

  @type header_app_types_bindings :: %{
          required(:run_mode_enum) => Core.c_source(),
          required(:msg_enum_members) => Core.c_source(),
          required(:msg_presence_macros) => Core.c_source(),
          required(:button_id_enum) => Core.c_source(),
          required(:button_event_macros) => Core.c_source(),
          required(:accel_axis_enum) => Core.c_source(),
          required(:scene_writer_late) => Core.c_source(),
          required(:entry_view_scene_append) => Core.c_symbol(),
          required(:draw_kind_enum) => Core.c_source(),
          required(:command_kind_enum) => Core.c_source(),
          required(:ui_node_kind_enum) => Core.c_source(),
          required(:phone_to_watch_target) => Core.msg_tag(),
          required(:watch_model_macros) => Core.c_source(),
          required(:watch_color_macros) => Core.c_source()
        }
end
