defmodule Ide.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  @spec start(Application.start_type(), term()) :: Supervisor.on_start()
  def start(_type, _args) do
    Application.put_env(
      :elm_ex,
      :package_source_roots,
      Ide.Debugger.CompileContract.package_source_roots()
    )

    repo =
      if release_runtime?() do
        Ide.RepoConfig.put_runtime_repo_config!()
      else
        Application.fetch_env!(:ide, :repo_module)
      end

    children = [
      IdeWeb.Telemetry,
      repo,
      Ide.Compiler.Cache,
      Ide.Compiler.ManifestCache,
      Ide.Mcp.CheckCache,
      Ide.Acp.AgentSupervisor,
      Ide.Debugger,
      {Registry, keys: :unique, name: Ide.Emulator.Registry},
      Ide.Emulator.SlotLimiter,
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

    with {:ok, pid} <- Supervisor.start_link(children, opts) do
      Ide.Emulator.StartupCheck.log()
      {:ok, pid}
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  @spec config_change(keyword(), keyword(), keyword()) :: :ok
  def config_change(changed, _new, removed) do
    IdeWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  @spec release_runtime?() :: boolean()
  defp release_runtime? do
    not is_nil(System.get_env("RELEASE_ROOT"))
  end
end
