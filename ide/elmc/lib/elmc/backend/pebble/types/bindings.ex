defmodule Elmc.Backend.Pebble.Types.Bindings do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types.Bindings.{Header, Msg, Runtime, Shim}

  @type header_msg_macros :: Header.header_msg_macros()
  @type msg_fragments :: Msg.msg_fragments()
  @type event_dispatch_bindings :: Runtime.event_dispatch_bindings()
  @type source_bindings :: Runtime.source_bindings()
  @type header_bindings :: Header.header_bindings()
  @type header_app_types_bindings :: Header.header_app_types_bindings()
  @type scene_build_bindings :: Runtime.scene_build_bindings()
  @type view_command_bindings :: Runtime.view_command_bindings()
  @type app_lifecycle_bindings :: Msg.app_lifecycle_bindings()
  @type shim_analysis :: Shim.shim_analysis()
end
