defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue.Decode.PathSettings.PathPayload.Epilogue do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
        #endif

    """
  end
end
