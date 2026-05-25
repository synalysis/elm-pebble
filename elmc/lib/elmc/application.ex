defmodule Elmc.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @spec start(Application.start_type(), any()) ::
          {:ok, pid()} | {:error, {:already_started, pid()} | atom() | String.t() | tuple()}
  @impl true
  def start(_type, _args) do
    children = [
      # Starts a worker by calling: Elmc.Worker.start_link(arg)
      # {Elmc.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Elmc.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
