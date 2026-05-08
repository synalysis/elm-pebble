defmodule Ide.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  @spec start(term(), term()) :: term()
  def start(_type, _args) do
    children = [
      IdeWeb.Telemetry,
      Ide.Repo,
      Ide.Compiler.Cache,
      Ide.Compiler.ManifestCache,
      Ide.Mcp.CheckCache,
      Ide.Acp.AgentSupervisor,
      Ide.Debugger,
      {Registry, keys: :unique, name: Ide.Emulator.Registry},
      {DynamicSupervisor, strategy: :one_for_one, name: Ide.Emulator.SessionSupervisor},
      {DNSCluster, query: Application.get_env(:ide, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Ide.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Ide.Finch},
      # Start a worker by calling: Ide.Worker.start_link(arg)
      # {Ide.Worker, arg},
      # Start to serve requests, typically the last entry
      IdeWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Ide.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  @spec config_change(term(), term(), term()) :: term()
  def config_change(changed, _new, removed) do
    IdeWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
