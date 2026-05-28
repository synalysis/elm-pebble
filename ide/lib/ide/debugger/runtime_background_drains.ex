defmodule Ide.Debugger.RuntimeBackgroundDrains do
  @moduledoc false

  alias Ide.Debugger.PendingHttpFollowups
  alias Ide.Debugger.PendingProtocolDelivery
  alias Ide.Debugger.RuntimeBackgroundWork

  @spec schedule_all(String.t(), map()) :: :ok
  def schedule_all(project_slug, state)
      when is_binary(project_slug) and is_map(state) do
    PendingProtocolDelivery.maybe_schedule_drain(project_slug, state)
    PendingHttpFollowups.maybe_schedule_drain(project_slug, state)
    :ok
  end

  @spec await_idle(String.t(), timeout()) :: :ok | :timeout
  def await_idle(project_slug, timeout \\ 120_000) do
    RuntimeBackgroundWork.await_idle(project_slug, timeout)
  end
end
