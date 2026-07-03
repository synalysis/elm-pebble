defmodule Elmc.Backend.Pebble.SourceWriter.Prologue do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.Prologue.{
    AppendFallbackScene,
    Defaults,
    DirectView,
    HeapLog,
    Includes,
    SceneLog,
    TraceMacros
  }

  @spec body(Types.c_macro_name(), keyword()) :: Types.c_source()
  def body(direct_view_macro, opts \\ []) do
    [
      Includes.body(),
      DirectView.body(direct_view_macro),
      AppendFallbackScene.body(Keyword.get(opts, :append_fallback_enabled?, false)),
      SceneLog.body(),
      TraceMacros.body(),
      HeapLog.body(),
      Defaults.body()
    ]
    |> IO.iodata_to_binary()
  end
end
