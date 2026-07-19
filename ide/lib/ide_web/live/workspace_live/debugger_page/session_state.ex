defmodule IdeWeb.WorkspaceLive.DebuggerPage.SessionState do
  @moduledoc false

  alias Ide.Debugger.Types, as: DebuggerTypes
  alias IdeWeb.WorkspaceLive.DebuggerBootstrapFlow

  @type bootstrap_status :: atom()
  @type debugger_state :: DebuggerTypes.runtime_state() | nil

  @spec bootstrap_busy?(bootstrap_status()) :: boolean()
  def bootstrap_busy?(:running), do: true
  def bootstrap_busy?(_), do: false

  @spec bootstrap_step_count() :: pos_integer()
  def bootstrap_step_count, do: DebuggerBootstrapFlow.bootstrap_step_count()

  @spec bootstrap_step_segments(pos_integer() | nil, pos_integer() | nil) :: [
          %{index: pos_integer(), status: :pending | :active | :done}
        ]
  def bootstrap_step_segments(step, total) when is_integer(step) and is_integer(total) and total > 0 do
    Enum.map(1..total, fn index ->
      status =
        cond do
          index < step -> :done
          index == step -> :active
          true -> :pending
        end

      %{index: index, status: status}
    end)
  end

  def bootstrap_step_segments(_step, _total), do: []

  @spec companion_bootstrap_busy?(bootstrap_status()) :: boolean()
  def companion_bootstrap_busy?(:running), do: true
  def companion_bootstrap_busy?(_), do: false

  @spec running?(debugger_state()) :: boolean()
  def running?(%{running: true}), do: true
  def running?(_), do: false

  @spec start_button_label(debugger_state(), bootstrap_status()) :: String.t()
  def start_button_label(_debugger_state, :running), do: "Starting…"

  def start_button_label(debugger_state, _status) do
    if running?(debugger_state), do: "Restart", else: "Start"
  end

  @spec visible_timeline_mode(String.t(), boolean()) :: String.t()
  def visible_timeline_mode(_mode, false), do: "watch"
  def visible_timeline_mode(mode, true), do: mode
end
