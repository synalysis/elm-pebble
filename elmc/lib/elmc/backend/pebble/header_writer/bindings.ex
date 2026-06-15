defmodule Elmc.Backend.Pebble.HeaderWriter.Bindings do
  @moduledoc false

  alias Elmc.Backend.Pebble.{CEmit, FeatureFlags, IRAnalysis, Kinds, MsgCodegen, SceneWriter, Types,
    Util}

  @type t :: Types.header_bindings()

  @button_event_macros """
  #define ELMC_BUTTON_EVENT_PRESSED 1
  #define ELMC_BUTTON_EVENT_RELEASED 2
  #define ELMC_BUTTON_EVENT_LONG_PRESSED 3
  """

  @spec from_analysis(Types.shim_analysis(), Types.entry_module(), keyword()) ::
          Types.header_bindings()
  def from_analysis(
        %{
          msg_constructors: msg_constructors,
          msg_constructor_payload_specs: msg_constructor_payload_specs,
          watch_model_tags: watch_model_tags,
          watch_color_tags: watch_color_tags,
          feature_flags: feature_flags,
          accel_config: accel_config
        },
        entry_module,
        opts \\ []
      ) do
    %{enum_members: msg_enum_members, presence_macros: msg_presence_macros} =
      MsgCodegen.header_macros(msg_constructors)

    %{
      scene_writer_early: SceneWriter.header_early_declarations(),
      feature_macros: FeatureFlags.macros(feature_flags),
      run_mode_enum: CEmit.c_enum("ElmcPebbleRunMode", "ELMC_PEBBLE_MODE", Kinds.run_modes()),
      msg_enum_members: msg_enum_members,
      msg_presence_macros: msg_presence_macros,
      button_id_enum: CEmit.c_enum("ElmcPebbleButtonId", "ELMC_PEBBLE_BUTTON", Kinds.button_ids()),
      button_event_macros: @button_event_macros,
      accel_axis_enum:
        CEmit.c_enum("ElmcPebbleAccelAxis", "ELMC_PEBBLE_ACCEL_AXIS", Kinds.accel_axes()),
      draw_kind_enum: CEmit.c_enum("ElmcPebbleDrawKind", "ELMC_PEBBLE_DRAW", Kinds.draw_kinds()),
      command_kind_enum:
        CEmit.c_enum("ElmcPebbleCommandKind", "ELMC_PEBBLE_CMD", Kinds.command_kinds()),
      ui_node_kind_enum:
        CEmit.c_enum("ElmcPebbleUiNodeKind", "ELMC_PEBBLE_UI", Kinds.ui_node_kinds()),
      scene_writer_late: SceneWriter.header_late_declarations(),
      entry_view_scene_append: Util.entry_fn_name(entry_module, "view_scene_append"),
      phone_to_watch_target:
        IRAnalysis.phone_to_watch_msg_target(msg_constructors, msg_constructor_payload_specs),
      watch_model_macros: CEmit.constructor_tag_macros("ELMC_PEBBLE_WATCH_MODEL", watch_model_tags),
      watch_color_macros: CEmit.constructor_tag_macros("ELMC_PEBBLE_WATCH_COLOR", watch_color_tags),
      accel_samples_per_update: Map.fetch!(accel_config, :samples_per_update),
      accel_sampling_hz: Map.fetch!(accel_config, :sampling_hz),
      aplite_direct_view_scene?: Keyword.get(opts, :aplite_direct_view_scene, false)
    }
  end
end
