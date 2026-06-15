defmodule IdeWeb.WorkspaceLive.DebuggerPage.SessionState do
  @moduledoc false

  @type bootstrap_status :: atom()
  @type debugger_state :: map() | nil

  @spec bootstrap_busy?(bootstrap_status()) :: boolean()
  def bootstrap_busy?(:running), do: true
  def bootstrap_busy?(_), do: false

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
