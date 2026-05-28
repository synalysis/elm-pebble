defmodule Ide.Debugger.RuntimeBackgroundNotify do
  @moduledoc """
  Notifies LiveView (and other subscribers) when debugger runtime work finishes
  outside the Agent lock (async HTTP, deferred AppMessage delivery).
  """

  @pubsub Ide.PubSub
  @topic_prefix "debugger:runtime:"

  @spec topic(String.t()) :: String.t()
  def topic(scope_key) when is_binary(scope_key), do: @topic_prefix <> scope_key

  @spec broadcast(String.t()) :: :ok
  def broadcast(scope_key) when is_binary(scope_key) do
    Phoenix.PubSub.broadcast(@pubsub, topic(scope_key), :debugger_runtime_updated)
    :ok
  end
end
