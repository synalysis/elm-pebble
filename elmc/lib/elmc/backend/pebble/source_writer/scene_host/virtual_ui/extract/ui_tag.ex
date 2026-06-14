defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.VirtualUi.Extract.UiTag do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    static int elmc_is_virtual_ui_tag(ElmcValue *value, int64_t encoded_tag) {
      if (!value) return 0;
      int64_t tag = elmc_as_int(value);
      return tag == encoded_tag;
    }

"""
  end
end
