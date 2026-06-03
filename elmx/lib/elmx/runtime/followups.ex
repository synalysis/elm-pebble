defmodule Elmx.Runtime.Followups do
  @moduledoc """
  Maps wire-format runtime commands to debugger `followup_messages` rows.

  `flatten_commands/1` expands `batch` and drops `none`. `protocol_events/1` extracts
  synthetic `debugger.protocol_tx` / `debugger.protocol_rx` timeline events.
  """

  alias Elmx.Runtime.Followups.{Commands, Flatten, Protocol}
  alias Elmx.Types

  @default_source_root "watch"

  defdelegate protocol_events(commands), to: Protocol, as: :events
  defdelegate flatten_commands(commands), to: Flatten, as: :flatten

  @spec from_commands(Types.wire_cmd() | [Types.wire_cmd()], Types.followups_opts()) ::
          [Types.followup_row()]
  def from_commands(commands, opts \\ []) do
    source_root = Keyword.get(opts, :source_root, @default_source_root)

    commands
    |> flatten_commands()
    |> Enum.flat_map(&Commands.to_followups(&1, source_root))
  end
end
