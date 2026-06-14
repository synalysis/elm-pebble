defmodule Elmc.Backend.Pebble.SourceWriter do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SourceWriter.{
    AppLifecycle,
    Bindings,
    DrawRuntime,
    EventDispatch,
    Prologue,
    SceneHost,
    DispatchCore,
    ViewRuntime
  }

  @spec generate(Types.shim_analysis(), Types.entry_module()) :: Types.c_source()
  def generate(analysis, entry_module) do
    bindings = Bindings.from_analysis(analysis, entry_module)

    [
      Prologue.body(bindings.direct_view_macro),
      bindings.msg.current_second_helper,
      DrawRuntime.body(),
      bindings.scene_writer_source,
      SceneHost.body(),
      bindings.msg.msg_constructor_arity_fn,
      DispatchCore.body(),
      EventDispatch.body(bindings),
      ViewRuntime.body(bindings),
      AppLifecycle.body(bindings)
    ]
    |> IO.iodata_to_binary()
  end
end
