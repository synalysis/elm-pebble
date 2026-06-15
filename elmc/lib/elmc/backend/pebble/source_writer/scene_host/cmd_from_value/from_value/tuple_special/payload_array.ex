defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.CmdFromValue.FromValue.TupleSpecial.PayloadArray do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
        int64_t payload[6] = {0, 0, 0, 0, 0, 0};
    """
  end
end
