defmodule Elmc.TestSupport.PlanStrictTemplates do
  @moduledoc false

  @strict_pass ~w(
    game_2048
    game_elmtris
    game_basic
    game_jump_n_run
    game_tiny_bird
    watchface_poke_battle
    watchface_yes
    watchface_analog
    watchface_digital
    watchface_minimal
    watchface_weather_animated
    watchface_tangram_time
    watchface_color_shapes
    watchface_smoke_screen
    watchface_tutorial_complete
    app_minimal
    watch_demo_accel
    watch_demo_app_focus
    watch_demo_compass
    watch_demo_data_log
    watch_demo_dictation
    watch_demo_drawing_showcase
    watch_demo_frame
    watch_demo_health
    watch_demo_launch
    watch_demo_light
    watch_demo_log
    watch_demo_screen_change
    watch_demo_speaker
    watch_demo_storage
    watch_demo_system
    watch_demo_time
    watch_demo_unobstructed
    watch_demo_vibes
    watch_demo_wakeup
    watch_demo_watch_info
    companion_demo_calendar
    companion_demo_geolocation
    companion_demo_phone_status
    companion_demo_protocol_matrix
    companion_demo_settings
    companion_demo_storage
    companion_demo_timeline
    companion_demo_weather_env
    companion_demo_websocket
    starter_watch
  )

  @spec names() :: [String.t()]
  def names, do: @strict_pass
end
