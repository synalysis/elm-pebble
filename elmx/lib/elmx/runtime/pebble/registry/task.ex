defmodule Elmx.Runtime.Pebble.Registry.Task do
  @moduledoc false

  alias Elmx.Runtime.Core.Task
  alias Elmx.Runtime.Handler

  @type handler :: Handler.t()

  @spec handlers() :: %{String.t() => handler()}
  def handlers do
    %{
      "elmx_core_task_map" => {Task, :map},
      "elmx_core_task_map2" => {Task, :map2, args: [0, 1, 2]},
      "elmx_core_task_and_then" => {Task, :and_then}
    }
  end
end
