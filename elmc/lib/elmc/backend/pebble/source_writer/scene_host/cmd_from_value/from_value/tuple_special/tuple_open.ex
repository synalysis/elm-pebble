defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.CmdFromValue.FromValue.TupleSpecial.TupleOpen do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
      if (value->tag == ELMC_TAG_TUPLE2 && value->payload != NULL) {
        ElmcTuple2 *tuple = (ElmcTuple2 *)value->payload;
        if (!tuple->first || !tuple->second) return -3;
        out_cmd->kind = elmc_as_int(tuple->first);

    """
  end
end
