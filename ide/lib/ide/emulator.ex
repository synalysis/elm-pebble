defmodule Ide.Emulator do
  @moduledoc """
  Runtime boundary for embedded Pebble emulator sessions.
  """

  alias Ide.Emulator.Session

  @type launch_opts :: [
          project_slug: String.t(),
          platform: String.t(),
          artifact_path: String.t() | nil,
          has_phone_companion: boolean()
        ]

  @spec launch(launch_opts()) :: {:ok, map()} | {:error, term()}
  def launch(opts) do
    spec = Session.child_spec(opts)

    case DynamicSupervisor.start_child(Ide.Emulator.SessionSupervisor, spec) do
      {:ok, pid} -> {:ok, Session.info(pid)}
      {:error, {:already_started, pid}} -> {:ok, Session.info(pid)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec runtime_status(term()) :: map()
  def runtime_status(platform \\ nil), do: Session.runtime_status(platform)

  @spec install_runtime_dependencies(term()) :: {:ok, map()} | {:error, term()}
  def install_runtime_dependencies(platform \\ nil),
    do: Session.install_runtime_dependencies(platform)

  @spec lookup(String.t()) :: {:ok, pid()} | {:error, :not_found}
  def lookup(id) when is_binary(id) do
    case Registry.lookup(Ide.Emulator.Registry, id) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @spec info(String.t()) :: {:ok, map()} | {:error, term()}
  def info(id) when is_binary(id) do
    with {:ok, pid} <- lookup(id) do
      {:ok, Session.info(pid)}
    end
  end

  @spec ping(String.t()) :: {:ok, map()} | {:error, term()}
  def ping(id) when is_binary(id) do
    with {:ok, pid} <- lookup(id) do
      Session.ping(pid)
    end
  end

  @spec install(String.t()) :: {:ok, map()} | {:error, term()}
  def install(id) when is_binary(id) do
    with {:ok, pid} <- lookup(id) do
      Session.install(pid)
    end
  end

  @spec kill(String.t()) :: :ok
  def kill(id) when is_binary(id) do
    case lookup(id) do
      {:ok, pid} -> Session.kill(pid)
      {:error, :not_found} -> :ok
    end
  end
end
