defmodule Elmc.Backend.Pebble.SourceWriter.Prologue.AppendFallbackScene do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body(boolean()) :: Types.c_source()
  def body(true) do
    "#define ELMC_PEBBLE_APPEND_FALLBACK_SCENE 1\n"
  end

  def body(false), do: ""
end
