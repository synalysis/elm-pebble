defmodule Elmx.Runtime.Pebble.Registry.Time do
  @moduledoc false

  alias Elmx.Runtime.Core.Time
  alias Elmx.Runtime.Handler
  alias Elmx.Runtime.Pebble.Dispatch

  @type handler :: Handler.t()

  @spec handlers() :: %{String.t() => handler()}
  def handlers do
    %{
      "elmx_time_now" => {Time, :now},
      "elmx_time_get_zone_name" => {Time, :get_zone_name},
      "elmx_kernel_time_now_millis" => {Dispatch, :kernel_time_now_millis},
      "elmx_kernel_time_zone_offset_minutes" => {Time, :zone_offset_minutes}
    }
  end
end
