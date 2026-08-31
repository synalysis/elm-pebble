defmodule Ide.Compiler.Quota do
  @moduledoc """
  Limits concurrent compiles/checks per tenant in public IDE modes.
  """

  use GenServer

  alias Ide.Auth

  @name __MODULE__

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  @spec checkout() :: :ok | {:error, :busy}
  def checkout do
    case max_concurrent() do
      :infinity ->
        :ok

      max when is_integer(max) ->
        GenServer.call(@name, {:checkout, tenant_key(), max})
    end
  end

  @spec checkin() :: :ok
  def checkin do
    case max_concurrent() do
      :infinity ->
        :ok

      _ ->
        GenServer.cast(@name, {:checkin, tenant_key()})
        :ok
    end
  end

  @spec with_quota((-> result)) :: result | {:error, :busy} when result: term()
  def with_quota(fun) when is_function(fun, 0) do
    case checkout() do
      :ok ->
        try do
          fun.()
        after
          checkin()
        end

      {:error, :busy} = error ->
        error
    end
  end

  @impl true
  def init(_opts) do
    {:ok, %{counts: %{}}}
  end

  @impl true
  def handle_call({:checkout, tenant, max}, _from, state) do
    count = Map.get(state.counts, tenant, 0)

    if count >= max do
      {:reply, {:error, :busy}, state}
    else
      {:reply, :ok, %{state | counts: Map.put(state.counts, tenant, count + 1)}}
    end
  end

  @impl true
  def handle_cast({:checkin, tenant}, state) do
    counts =
      case Map.get(state.counts, tenant, 0) do
        n when n <= 1 -> Map.delete(state.counts, tenant)
        n -> Map.put(state.counts, tenant, n - 1)
      end

    {:noreply, %{state | counts: counts}}
  end

  @spec tenant_key() :: {:user, integer()} | :local
  defp tenant_key do
    case Process.get(:ide_current_user) do
      %{id: id} when is_integer(id) -> {:user, id}
      _ -> :local
    end
  end

  @spec max_concurrent() :: pos_integer() | :infinity
  defp max_concurrent do
    if Auth.public_mode?() do
      Application.get_env(:ide, __MODULE__, [])
      |> Keyword.get(:max_concurrent, 2)
      |> max(1)
    else
      :infinity
    end
  end
end
