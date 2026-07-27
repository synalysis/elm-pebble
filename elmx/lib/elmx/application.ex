defmodule Elmx.Application do
  @moduledoc false
  alias Elmx.Types, as: Types

  use Application

  @impl true
  @spec start(Types.elm_value(), [String.t()]) :: Types.elm_value()

  def start(_type, _args) do
    children = [
      Elmx.Runtime.ModuleRegistry
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Elmx.Supervisor)
  end
end
