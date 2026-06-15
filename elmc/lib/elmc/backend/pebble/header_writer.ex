defmodule Elmc.Backend.Pebble.HeaderWriter do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.HeaderWriter.{
    AccelDefaults,
    ApiDecls,
    AppTypes,
    Bindings,
    Epilogue,
    Prologue,
    SceneConfig,
    SubscriptionFlags
  }

  @spec generate(Types.shim_analysis(), Types.entry_module(), keyword()) :: Types.c_source()
  def generate(analysis, entry_module, opts \\ []) do
    bindings =
      Bindings.from_analysis(analysis, entry_module)
      |> Map.put(
        :aplite_direct_view_scene?,
        Keyword.get(opts, :aplite_direct_view_scene, false)
      )

    [
      Prologue.body(bindings),
      SceneConfig.body(),
      AppTypes.body(bindings),
      SubscriptionFlags.body(),
      AccelDefaults.body(bindings),
      ApiDecls.body(),
      Epilogue.body()
    ]
    |> IO.iodata_to_binary()
  end
end
