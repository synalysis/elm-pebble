defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec.PayloadLen.KindSwitch.DefaultCase do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
      default:
        return ELMC_SCENE_PL_FULL;
      }
    }
"""
  end
end
