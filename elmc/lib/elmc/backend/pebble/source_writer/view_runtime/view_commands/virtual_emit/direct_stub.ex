defmodule Elmc.Backend.Pebble.SourceWriter.ViewRuntime.ViewCommands.VirtualEmit.DirectStub do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
      #else
        return -11;
      #endif
    }
    """
  end
end
