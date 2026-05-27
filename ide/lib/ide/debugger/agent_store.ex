defmodule Ide.Debugger.AgentStore do
  @moduledoc false

  alias Ide.Debugger.SessionDefaults
  alias Ide.Debugger.Types

  @default_agent Ide.Debugger
  # Must cover long `get_and_update` reloads and `get` reads queued behind them (Agent default is 5s).
  @default_timeout_ms 120_000

  @type store :: %{optional(String.t()) => Types.runtime_state()}
  @type prepare_fn :: (Types.runtime_state() -> Types.runtime_state())
  @type default_state_fn :: (String.t() -> Types.runtime_state())
  @type on_remove_fn :: (Types.runtime_state() -> any())

  @spec update(
          String.t(),
          (Types.runtime_state() -> Types.runtime_state()),
          keyword()
        ) :: {:ok, Types.runtime_state()}
  def update(project_slug, updater, opts \\ []) when is_binary(project_slug) and is_function(updater, 1) do
    agent = Keyword.get(opts, :agent, @default_agent)
    timeout = Keyword.get(opts, :timeout, @default_timeout_ms)
    prepare = Keyword.get(opts, :prepare, &SessionDefaults.ensure_phone_state/1)
    default_state = Keyword.get(opts, :default_state, &SessionDefaults.default_state/1)

    :ok = ensure_started(agent)

    updated =
      Agent.get_and_update(
        agent,
        fn store ->
          current =
            store
            |> fetch_or_default(project_slug, default_state)
            |> prepare.()

          next = updater.(current)
          {next, Map.put(store, project_slug, next)}
        end,
        timeout
      )

    {:ok, updated}
  end

  @spec fetch(String.t(), keyword()) :: Types.runtime_state()
  def fetch(project_slug, opts \\ []) when is_binary(project_slug) do
    agent = Keyword.get(opts, :agent, @default_agent)
    timeout = Keyword.get(opts, :timeout, @default_timeout_ms)
    prepare = Keyword.get(opts, :prepare, &SessionDefaults.ensure_phone_state/1)
    default_state = Keyword.get(opts, :default_state, &SessionDefaults.default_state/1)
    transform = Keyword.get(opts, :transform, & &1)

    :ok = ensure_started(agent)

    Agent.get(
      agent,
      fn store ->
        store
        |> fetch_or_default(project_slug, default_state)
        |> prepare.()
        |> transform.()
      end,
      timeout
    )
  end

  @spec put(String.t(), Types.runtime_state(), keyword()) :: Types.runtime_state()
  def put(session_key, state, opts \\ []) when is_binary(session_key) and is_map(state) do
    agent = Keyword.get(opts, :agent, @default_agent)
    timeout = Keyword.get(opts, :timeout, @default_timeout_ms)
    prepare = Keyword.get(opts, :prepare, &SessionDefaults.ensure_phone_state/1)
    on_previous = Keyword.get(opts, :on_previous, fn _previous -> :ok end)

    :ok = ensure_started(agent)

    Agent.get_and_update(
      agent,
      fn store ->
      case Map.get(store, session_key) do
        previous when is_map(previous) -> on_previous.(previous)
        _ -> :ok
      end

      prepared = prepare.(state)
      {prepared, Map.put(store, session_key, prepared)}
    end,
      timeout
    )
  end

  @spec forget(String.t(), keyword()) :: :ok
  def forget(project_slug, opts \\ []) when is_binary(project_slug) do
    agent = Keyword.get(opts, :agent, @default_agent)
    on_remove = Keyword.get(opts, :on_remove, fn _state -> :ok end)

    :ok = ensure_started(agent)

    Agent.update(agent, fn store ->
      case Map.pop(store, project_slug) do
        {state, next_store} when is_map(state) ->
          on_remove.(state)
          next_store

        {_state, next_store} ->
          next_store
      end
    end)
  end

  @spec fetch_or_default(store(), String.t(), default_state_fn()) :: Types.runtime_state()
  def fetch_or_default(store, project_slug, default_state) when is_map(store) and is_function(default_state, 1) do
    case Map.fetch(store, project_slug) do
      {:ok, state} -> state
      :error -> default_state.(project_slug)
    end
  end

  @spec ensure_started(atom() | pid()) :: :ok
  def ensure_started(agent \\ @default_agent)

  def ensure_started(pid) when is_pid(pid) do
    if Process.alive?(pid), do: :ok, else: raise "debugger agent is not alive: #{inspect(pid)}"
  end

  def ensure_started(agent) when is_atom(agent) do
    case Process.whereis(agent) do
      pid when is_pid(pid) ->
        :ok

      nil ->
        case apply(agent, :start_link, [[]]) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, reason} -> raise "failed to start debugger agent: #{inspect(reason)}"
        end
    end
  end
end
