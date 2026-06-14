defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.DirtyRegion.CmdBounds.VisualBounds.CircleDefault do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
        case ELMC_PEBBLE_DRAW_CIRCLE:
        case ELMC_PEBBLE_DRAW_FILL_CIRCLE: {
          int r = cmd->p2 < 0 ? 0 : cmd->p2;
          elmc_rect_set(out, cmd->p0 - r, cmd->p1 - r, r * 2 + 1, r * 2 + 1);
          return !elmc_rect_empty(out);
        }
        default:
          return 0;
      }
    }

    """
  end
end
