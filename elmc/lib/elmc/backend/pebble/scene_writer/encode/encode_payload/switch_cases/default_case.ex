defmodule Elmc.Backend.Pebble.SceneWriter.Encode.EncodePayload.SwitchCases.DefaultCase do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
          default:
            break;
          }
    """
  end
end
