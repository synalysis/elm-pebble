defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.DirtyRegion.Compute.RecordDiff.Finish do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
      app->dirty_rect = union_rect;
      app->dirty_rect_full = 0;
      app->dirty_rect_valid = 1;
    }
"""
  end
end
