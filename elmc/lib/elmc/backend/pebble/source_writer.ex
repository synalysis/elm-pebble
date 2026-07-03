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

  @spec generate(Types.shim_analysis(), Types.entry_module(), keyword()) :: Types.c_source()
  def generate(analysis, entry_module, opts \\ []) do
    bindings =
      analysis
      |> Bindings.from_analysis(entry_module)
      |> Map.put(:append_fallback_enabled?, Keyword.get(opts, :append_fallback_enabled?, false))

    [
      Prologue.body(bindings.direct_view_macro,
        append_fallback_enabled?: Map.get(bindings, :append_fallback_enabled?, false)
      ),
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
