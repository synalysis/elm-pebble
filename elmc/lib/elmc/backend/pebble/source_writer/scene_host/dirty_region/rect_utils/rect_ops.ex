defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.DirtyRegion.RectUtils.RectOps do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    static int elmc_rect_empty(const ElmcPebbleRect *rect) {
      return !rect || rect->w <= 0 || rect->h <= 0;
    }

    static void elmc_rect_set(ElmcPebbleRect *rect, int x, int y, int w, int h) {
      if (!rect) return;
      rect->x = x;
      rect->y = y;
      rect->w = w < 0 ? 0 : w;
      rect->h = h < 0 ? 0 : h;
    }

    static int elmc_min_int(int a, int b) { return a < b ? a : b; }
    static int elmc_max_int(int a, int b) { return a > b ? a : b; }

    static void elmc_rect_union_into(ElmcPebbleRect *acc, const ElmcPebbleRect *rect) {
      if (!acc || elmc_rect_empty(rect)) return;
      if (elmc_rect_empty(acc)) {
        *acc = *rect;
        return;
      }
      int x1 = elmc_min_int(acc->x, rect->x);
      int y1 = elmc_min_int(acc->y, rect->y);
      int x2 = elmc_max_int(acc->x + acc->w, rect->x + rect->w);
      int y2 = elmc_max_int(acc->y + acc->h, rect->y + rect->h);
      acc->x = x1;
      acc->y = y1;
      acc->w = x2 - x1;
      acc->h = y2 - y1;
    }

    """
  end
end
