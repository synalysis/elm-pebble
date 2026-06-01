defmodule Elmx.Runtime.Core.Time do
  @moduledoc false

  @spec now_millis() :: integer()
  def now_millis, do: System.system_time(:millisecond)

  @spec zone_offset_minutes() :: integer()
  def zone_offset_minutes, do: 0
end
