defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.DirtyRegion.Compute.RecordDiff.Preamble do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
      int old_offset = 0;
      int new_offset = 0;
      ElmcPebbleRect union_rect = {0, 0, 0, 0};

      while (old_offset < app->prev_scene.byte_count || new_offset < app->scene.byte_count) {
"""
  end
end
