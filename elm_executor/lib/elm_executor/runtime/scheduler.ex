defmodule ElmExecutor.Runtime.Scheduler do
  @moduledoc """
  Deterministic logical scheduler for ElmExecutor runtime events.

  This scheduler intentionally uses a logical clock (`seq`) so replayability is
  stable across runs independent of wall clock time.
  """

  @type event :: %{
          seq: non_neg_integer(),
          type: String.t(),
          message: String.t() | nil,
          payload: map()
        }

  @type t :: %__MODULE__{
          seq: non_neg_integer(),
          queue: [event()],
          history: [event()]
        }

  defstruct seq: 0, queue: [], history: []

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec enqueue(t(), String.t(), String.t() | nil, map()) :: t()
  def enqueue(%__MODULE__{} = scheduler, type, message, payload \\ %{})
      when is_binary(type) and (is_binary(message) or is_nil(message)) and is_map(payload) do
    event = %{
      seq: scheduler.seq + 1 + length(scheduler.queue),
      type: type,
      message: message,
      payload: payload
    }

    %{scheduler | queue: scheduler.queue ++ [event]}
  end

  @spec dequeue(t()) :: {:ok, event(), t()} | :empty
  def dequeue(%__MODULE__{queue: [event | rest]} = scheduler) do
    next = %{
      scheduler
      | seq: event.seq,
        queue: rest
    }

    {:ok, event, next}
  end

  def dequeue(%__MODULE__{}), do: :empty

  @spec record(t(), event()) :: t()
  def record(%__MODULE__{} = scheduler, event) when is_map(event) do
    %{scheduler | history: [event | scheduler.history] |> Enum.take(500)}
  end

  @spec replay_recent(t(), pos_integer()) :: [event()]
  def replay_recent(%__MODULE__{} = scheduler, count) when is_integer(count) and count > 0 do
    scheduler.history
    |> Enum.take(count)
    |> Enum.reverse()
  end
end
