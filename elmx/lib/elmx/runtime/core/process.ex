defmodule Elmx.Runtime.Core.Process do
  @moduledoc false

  alias Elmx.Types

  @spec spawn(Types.elm_hof()) :: Types.result_native()
  def spawn(_task), do: {:Ok, next_pid()}

  @spec sleep(integer()) :: Types.result_native()
  def sleep(_milliseconds), do: {:Ok, 0}

  @spec kill(integer()) :: Types.result_native()
  def kill(_pid), do: {:Ok, 0}

  defp next_pid do
  :atomics.add(pid_counter(), 1, 1)
  :atomics.get(pid_counter(), 1)
  end

  defp pid_counter do
    case :persistent_term.get({__MODULE__, :counter}, nil) do
      nil ->
        counter = :atomics.new(1, signed: false)
        :atomics.put(counter, 1, 0)
        :persistent_term.put({__MODULE__, :counter}, counter)
        counter

      counter ->
        counter
    end
  end
end
