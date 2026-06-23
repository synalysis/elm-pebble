defmodule Elmc.Backend.Pebble.FeatureFlags.CommandFlags.Storage do
  @moduledoc false

  alias Elmc.Backend.Pebble.FeatureFlags.TargetSet
  alias Elmc.Backend.Pebble.Types

  @spec compute(Types.call_target_set()) :: Types.command_storage_flags()
  def compute(targets) do
    %{
      cmd_storage_write_int: TargetSet.member?(targets, "Pebble.Cmd.storageWriteInt"),
      cmd_storage_read_int: TargetSet.member?(targets, "Pebble.Cmd.storageReadInt"),
      cmd_storage_write_string:
        TargetSet.member?(targets, "Pebble.Storage.writeString") or
          TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.storageWriteString"),
      cmd_storage_read_string:
        TargetSet.member?(targets, "Pebble.Storage.readString") or
          TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.storageReadString"),
      cmd_random_generate:
        TargetSet.member?(targets, "Random.generate") or
          TargetSet.member?(targets, "Elm.Kernel.Random.generate"),
      cmd_storage_delete: TargetSet.member?(targets, "Pebble.Cmd.storageDelete"),
      cmd_storage_read_max_size:
        TargetSet.member?(targets, "Pebble.Storage.maxSize") or
          TargetSet.member?(targets, "Elm.Kernel.PebbleWatch.storageReadMaxSize"),
      cmd_companion_send: TargetSet.member?(targets, "Pebble.Internal.Companion.companionSend")
    }
  end
end
