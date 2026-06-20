defmodule Elmx.Runtime.Core.Time do
  @moduledoc false

  alias Elmx.Runtime.Core.Task
  alias Elmx.Runtime.Values
  alias Elmx.Types

  @spec now() :: Types.task_native()
  def now, do: Task.succeed(:os.system_time(:millisecond))

  @spec get_zone_name() :: Types.task_native()
  def get_zone_name do
    offset_min = div(DateTime.utc_now().utc_offset, 60)
    Task.succeed(Values.ctor("Offset", [offset_min]))
  end

  @spec zone_offset_minutes() :: integer()
  def zone_offset_minutes, do: div(DateTime.utc_now().utc_offset, 60)
end
