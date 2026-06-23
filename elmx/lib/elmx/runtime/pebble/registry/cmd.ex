defmodule Elmx.Runtime.Pebble.Registry.Cmd do
  @moduledoc false

  alias Elmx.Runtime.Handler
  alias Elmx.Runtime.Pebble.Dispatch
  alias Elmx.Runtime.Values

  @type handler :: Handler.t()

  @spec handlers() :: %{String.t() => handler()}
  def handlers do
    %{
      "elmx_cmd_batch" => {Values, :cmd_batch},
      "elmx_cmd_map" => {Values, :cmd_map},
      "elmx_sub_map" => {Values, :sub_map},
      "elmx_sub_batch" => {Values, :sub_batch},
      "elmx_port_outgoing" => {Values, :port_outgoing},
      "elmx_port_incoming_sub" => {Values, :port_incoming_sub},
      "elmx_cmd_random_generate" => {Dispatch, :random_generate_cmd},
      "elmx_cmd_timer_after" => {Dispatch, :timer_after_cmd},
      "elmx_cmd_backlight" => {Dispatch, :backlight_cmd},
      "elmx_light_enable" => {Dispatch, :light_enable},
      "elmx_light_disable" => {Dispatch, :light_disable},
      "elmx_light_interaction" => {Dispatch, :light_interaction},
      "elmx_platform_application" => {Dispatch, :platform_application},
      "elmx_platform_watchface" => {Dispatch, :platform_watchface},
      "elmx_events_batch" => {Dispatch, :events_batch},
      "elmx_vibes_short_pulse" => {Dispatch, :vibes_short_pulse},
      "elmx_vibes_long_pulse" => {Dispatch, :vibes_long_pulse},
      "elmx_vibes_double_pulse" => {Dispatch, :vibes_double_pulse},
      "elmx_vibes_pattern" => {Dispatch, :vibes_pattern_cmd},
      "elmx_vibes_cancel" => {Dispatch, :vibes_cancel},
      "elmx_dictation_start" => {Dispatch, :dictation_start},
      "elmx_dictation_stop" => {Dispatch, :dictation_stop},
      "elmx_collision_rect_rect" => {Dispatch, :collision_rect_rect},
      "elmx_datalog_tag" => {Dispatch, :datalog_tag_value},
      "elmx_datalog_log_int32" => {Dispatch, :datalog_log_int32_cmd},
      "elmx_datalog_log_bytes" => {Dispatch, :datalog_log_bytes_cmd},
      "elmx_storage_read_int" => {Dispatch, :storage_read_int_cmd},
      "elmx_storage_read_string" => {Dispatch, :storage_read_string_cmd},
      "elmx_storage_write_int" => {Dispatch, :storage_write_int_cmd},
      "elmx_storage_write_string" => {Dispatch, :storage_write_string_cmd},
      "elmx_storage_delete" => {Dispatch, :storage_delete_cmd},
      "elmx_storage_read_max_size" => {Dispatch, :storage_read_max_size_cmd},
      "elmx_speaker_play_tone" => {Dispatch, :speaker_play_tone_cmd},
      "elmx_speaker_play_notes" => {Dispatch, :speaker_play_notes_cmd},
      "elmx_speaker_play_tracks" => {Dispatch, :speaker_play_tracks_cmd},
      "elmx_speaker_stop" => {Dispatch, :speaker_stop_cmd},
      "elmx_speaker_set_volume" => {Dispatch, :speaker_set_volume_cmd},
      "elmx_speaker_stream_open" => {Dispatch, :speaker_stream_open_cmd},
      "elmx_speaker_stream_write" => {Dispatch, :speaker_stream_write_cmd},
      "elmx_speaker_stream_close" => {Dispatch, :speaker_stream_close_cmd},
      "elmx_subscription_call" => {Dispatch, :subscription_call},
      "elmx_frame_every" => {Dispatch, :frame_every_cmd},
      "elmx_frame_at_fps" => {Dispatch, :frame_at_fps_cmd},
      "elmx_unobstructed_current_bounds" => {Dispatch, :unobstructed_current_bounds_cmd},
      "elmx_compass_peek" => {Dispatch, :compass_peek_cmd}
    }
  end
end
