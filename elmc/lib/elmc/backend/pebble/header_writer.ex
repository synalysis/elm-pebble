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

  @spec generate(Types.shim_analysis(), Types.entry_module()) :: Types.c_source()
  def generate(analysis, entry_module) do
    bindings = Bindings.from_analysis(analysis, entry_module)

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
