defmodule Elmx.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Elmx.Runtime.ModuleRegistry
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Elmx.Supervisor)
  end
end
