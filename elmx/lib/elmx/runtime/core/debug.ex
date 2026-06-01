defmodule Elmx.Runtime.Core.Debug do
  @moduledoc false

  require Logger

  @spec log(term(), term()) :: term()
  def log(label, value) do
    Logger.debug(fn -> "#{inspect(label)}: #{inspect(value)}" end)
    value
  end

  @spec todo(term()) :: no_return()
  def todo(label), do: raise "Debug.todo: #{inspect(label)}"

  @spec to_string(term()) :: binary()
  def to_string(value), do: inspect(value, limit: :infinity, printable_limit: :infinity)
end
