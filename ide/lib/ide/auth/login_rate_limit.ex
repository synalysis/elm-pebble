defmodule Ide.Auth.LoginRateLimit do
  @moduledoc """
  Fixed-window rate limits for magic-link login requests.

  Tracks separate counters per client IP and per email hash.
  """

  use GenServer

  @table :ide_login_rate_limit

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec allowed?(:ip | :email, String.t()) :: boolean()
  def allowed?(scope, key) when scope in [:ip, :email] and is_binary(key) do
    GenServer.call(__MODULE__, {:allowed?, scope, key})
  end

  @spec record(:ip | :email, String.t()) :: :ok
  def record(scope, key) when scope in [:ip, :email] and is_binary(key) do
    GenServer.cast(__MODULE__, {:record, scope, key})
    :ok
  end

  @spec reset() :: :ok
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    {:ok, %{}}
  end

  @impl true
  def handle_call({:allowed?, scope, key}, _from, state) do
    {limit, period_ms} = config(scope)
    bucket = bucket(period_ms)
    count = lookup_count(scope, key, bucket)
    {:reply, count < limit, state}
  end

  def handle_call(:reset, _from, state) do
    :ets.delete_all_objects(@table)
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:record, scope, key}, state) do
    {_, period_ms} = config(scope)
    bucket = bucket(period_ms)
    :ets.update_counter(@table, {scope, key, bucket}, {2, 1}, {{scope, key, bucket}, 0})
    {:noreply, state}
  end

  @spec lookup_count(:ip | :email, String.t(), integer()) :: non_neg_integer()
  defp lookup_count(scope, key, bucket) do
    case :ets.lookup(@table, {scope, key, bucket}) do
      [{{^scope, ^key, ^bucket}, count}] when is_integer(count) -> count
      _ -> 0
    end
  end

  @spec bucket(pos_integer()) :: integer()
  defp bucket(period_ms) do
    div(System.system_time(:millisecond), period_ms)
  end

  @spec config(:ip | :email) :: {pos_integer(), pos_integer()}
  defp config(scope) do
    defaults =
      case scope do
        :ip -> [limit: 20, period_ms: 3_600_000]
        :email -> [limit: 5, period_ms: 3_600_000]
      end

    overrides =
      Application.get_env(:ide, __MODULE__, [])
      |> Keyword.get(scope, [])

    opts = Keyword.merge(defaults, overrides)
    {Keyword.fetch!(opts, :limit), Keyword.fetch!(opts, :period_ms)}
  end
end
