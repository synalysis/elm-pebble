defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.VirtualUi.Hash do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.SceneHost.VirtualUi.Hash.{
    ListTag,
    Scalars,
    StringTag,
    TupleTag
  }

  @spec body() :: Types.c_source()
  def body do
    [
      """
      static uint64_t elmc_hash_value(ElmcValue *value, int depth) {
        if (!value || depth > 64) return 1469598103934665603ULL;
        uint64_t h = 1469598103934665603ULL;
        h ^= (uint64_t)value->tag;
        h *= 1099511628211ULL;

        switch (value->tag) {
      """,
      Scalars.body(),
      StringTag.body(),
      ListTag.body(),
      TupleTag.body(),
      """
        }
      }

      """
    ]
    |> IO.iodata_to_binary()
  end
end
