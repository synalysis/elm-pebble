defmodule Ide.Debugger.AppMessageQueueTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.AppMessageQueue

  test "enqueue and drain preserve FIFO order per surface" do
    state = %{app_message_queues: AppMessageQueue.empty()}
    payload_a = %{to: "companion", message: "RequestFigure"}
    payload_b = %{to: "companion", message: "ProvideFigure"}

    state = AppMessageQueue.enqueue(state, :companion, payload_a)
    state = AppMessageQueue.enqueue(state, :companion, payload_b)

    assert AppMessageQueue.pending?(state, :companion)

    {state, drained} = AppMessageQueue.drain_entries(state, :companion)

    assert drained == [payload_a, payload_b]
    refute AppMessageQueue.pending?(state, :companion)
  end
end
