defmodule Elmc.Backend.Pebble.FeatureFlags.CommandFlags.System.Logging do
  @moduledoc false

  alias Elmc.Backend.Pebble.FeatureFlags.TargetSet
  alias Elmc.Backend.Pebble.Types

  @spec compute(Types.call_target_set()) :: Types.command_logging_flags()
  def compute(targets) do
    %{
      cmd_log_info_code: TargetSet.member?(targets, "Pebble.Cmd.logInfoCode"),
      cmd_log_warn_code: TargetSet.member?(targets, "Pebble.Cmd.logWarnCode"),
      cmd_log_error_code: TargetSet.member?(targets, "Pebble.Cmd.logErrorCode")
    }
  end
end
