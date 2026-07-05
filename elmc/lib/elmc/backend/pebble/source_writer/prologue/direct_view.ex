defmodule Elmc.Backend.Pebble.SourceWriter.Prologue.DirectView do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body(Types.c_macro_name()) :: Types.c_source()
  def body(direct_view_macro) do
    """
    #if defined(#{direct_view_macro}) && \\
        (defined(ELMC_PEBBLE_APLITE_DIRECT_VIEW_SCENE) || !defined(ELMC_PEBBLE_PLATFORM))
    #define ELMC_PEBBLE_DIRECT_VIEW_SCENE 1
    #endif

    """
  end
end
