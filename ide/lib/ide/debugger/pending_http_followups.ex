defmodule Ide.Debugger.PendingHttpFollowups do
  @moduledoc """
  Runs deferred `elm/http` follow-ups outside the debugger Agent lock.

  Flights run sequentially per project (FIFO) so companion follow-up chains and
  protocol enqueue order stay consistent. Duplicate method+URL requests are
  skipped while pending, in-flight, or already completed in the session.
  """

  alias Ide.Debugger.AgentHosts
  alias Ide.Debugger.AgentSession
  alias Ide.Debugger.AgentStore
  alias Ide.Debugger.HttpFlightCommit
  alias Ide.Debugger.RuntimeBackgroundDrains
  alias Ide.Debugger.RuntimeBackgroundWork
  alias Ide.Debugger.RuntimeFollowups
  alias Ide.Debugger.SurfaceTargets
  alias Ide.Debugger.Types

  @pending_key :pending_http_followups
  @completed_key :completed_http_flights
  @drain_lock_table :debugger_http_drain_lock
  @in_flight_table :debugger_http_in_flight

  @spec async?() :: boolean()
  def async? do
    Application.get_env(:ide, :debugger_async_http_followups, true)
  end

  @spec maybe_schedule_drain(String.t(), Types.runtime_state()) :: :ok
  def maybe_schedule_drain(project_slug, state)
      when is_binary(project_slug) and is_map(state) do
    if async?() and pending(state) != [] do
      ensure_drain_lock_table()

      case :ets.lookup(@drain_lock_table, project_slug) do
        [{^project_slug, true}] ->
          :ok

        _ ->
          :ets.insert(@drain_lock_table, {project_slug, true})

          hosts = AgentSession.hosts()
          ctx = hosts |> AgentHosts.contexts() |> Map.fetch!(:runtime_followups)

          RuntimeBackgroundWork.spawn(project_slug, fn ->
            try do
              drain_until_empty(project_slug, ctx)
            after
              release_drain_lock(project_slug)

              st = AgentStore.fetch(project_slug)

              if pending(st) != [] do
                maybe_schedule_drain(project_slug, st)
              end
            end
          end)
      end
    end

    :ok
  end

  defp drain_until_empty(project_slug, ctx)
       when is_binary(project_slug) and is_map(ctx) do
    items = project_slug |> AgentStore.fetch() |> pending()

    if items != [] do
      {:ok, _} =
        AgentSession.mutate(project_slug, fn st ->
          put_pending(st, [])
        end)

      Enum.each(items, &run_flight(project_slug, &1, ctx))
      drain_until_empty(project_slug, ctx)
    else
      :ok
    end
  end

  @spec pending(Types.runtime_state()) :: [Types.pending_http_followup_item()]
  def pending(state) when is_map(state) do
    case Map.get(state, @pending_key) || Map.get(state, to_string(@pending_key)) do
      commands when is_list(commands) -> commands
      _ -> legacy_companion_pending(state)
    end
  end

  @spec enqueue(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          String.t(),
          Types.cmd_call(),
          String.t() | nil
        ) :: Types.runtime_state()
  def enqueue(state, target, target_name, package, command, followup_message)
      when is_map(state) and target in [:watch, :companion, :phone] and is_binary(target_name) and
             is_binary(package) and is_map(command) do
    if http_command_redundant?(state, command) do
      state
    else
      item = %{
        "target" => Atom.to_string(target),
        "target_name" => target_name,
        "package" => package,
        "command" => command,
        "followup_message" => followup_message
      }

      Map.update(state, @pending_key, [item], &(&1 ++ [item]))
    end
  end

  @spec http_command_redundant?(Types.runtime_state(), Types.cmd_call()) :: boolean()
  defp http_command_redundant?(state, command) when is_map(state) and is_map(command) do
    key = http_flight_key(command)

    http_command_pending?(state, command) or
      MapSet.member?(completed_flights(state), key) or
      http_in_flight?(key)
  end

  @spec http_command_pending?(Types.runtime_state(), Types.cmd_call()) :: boolean()
  defp http_command_pending?(state, command) when is_map(state) and is_map(command) do
    key = http_flight_key(command)

    Enum.any?(pending(state), fn item ->
      http_flight_key(Map.get(item, "command") || %{}) == key
    end)
  end

  @spec http_flight_key(Types.cmd_call()) :: {String.t(), String.t() | nil}
  defp http_flight_key(command) when is_map(command) do
    method =
      Map.get(command, "method") || Map.get(command, :method) || "GET"
      |> to_string()
      |> String.upcase()

    url = Map.get(command, "url") || Map.get(command, :url)

    {method, url}
  end

  @spec launch_flight(
          String.t(),
          Types.pending_http_followup_item(),
          RuntimeFollowups.apply_ctx()
        ) :: :ok
  def launch_flight(project_slug, item, ctx)
      when is_binary(project_slug) and is_map(item) and is_map(ctx) do
    RuntimeBackgroundWork.spawn(project_slug, fn -> run_flight(project_slug, item, ctx) end)
  end

  @spec run_flight(String.t(), Types.pending_http_followup_item(), RuntimeFollowups.apply_ctx()) ::
          :ok
  def run_flight(project_slug, item, ctx)
      when is_binary(project_slug) and is_map(item) and is_map(ctx) do
    {target, target_name, package, command, followup_message} = flight_fields(item)
    key = http_flight_key(command)

    if http_in_flight?(key) or completed_flight?(project_slug, key) do
      :ok
    else
      mark_http_in_flight(key)

      try do
        run_flight_locked(
          project_slug,
          target,
          target_name,
          package,
          command,
          followup_message,
          ctx
        )
      after
        clear_http_in_flight(key)
      end
    end
  end

  defp run_flight_locked(
         project_slug,
         target,
         target_name,
         package,
         command,
         followup_message,
         ctx
       ) do
    # Snapshot + HTTP + runtime step run outside the Agent lock. Commit merges onto the
    # latest locked state so concurrent protocol delivery (for example ProvideFigure)
    # is not reverted while CatalogReceived chains into SvgReceived.
    basis = AgentStore.fetch(project_slug, timeout: flight_fetch_timeout_ms())
    result = execute_flight_http(basis, target, command, ctx)

    applied_state =
      RuntimeFollowups.apply_http_executor_result(
        basis,
        target,
        target_name,
        package,
        command,
        followup_message,
        result,
        ctx
      )

    {:ok, state} =
      AgentSession.mutate(project_slug, fn current ->
        HttpFlightCommit.commit(current, applied_state, basis, target)
        |> mark_http_completed(command)
      end)

    RuntimeBackgroundDrains.schedule_all(project_slug, state)
    :ok
  end

  @flight_fetch_timeout_ms 180_000

  @spec flight_fetch_timeout_ms() :: pos_integer()
  defp flight_fetch_timeout_ms, do: @flight_fetch_timeout_ms

  defp execute_flight_http(state, target, command, ctx) do
    RuntimeFollowups.execute_http_command(state, target, command, ctx)
  end

  defp flight_fields(item) when is_map(item) do
    target =
      item
      |> Map.get("target")
      |> SurfaceTargets.normalize()

    target_name = Map.get(item, "target_name") || ""
    package = Map.get(item, "package") || "elm/http"
    command = Map.get(item, "command") || %{}
    followup_message = Map.get(item, "followup_message")

    {target, target_name, package, command, followup_message}
  end

  defp put_pending(state, items) when is_map(state) and is_list(items) do
    state
    |> Map.put(@pending_key, items)
    |> drop_legacy_companion_pending()
  end

  defp legacy_companion_pending(state) do
    case Map.get(state, :companion) do
      %{@pending_key => commands} when is_list(commands) -> commands
      %{"pending_http_followups" => commands} when is_list(commands) -> commands
      _ -> []
    end
  end

  defp drop_legacy_companion_pending(state) do
    update_in(state, [:companion], fn
      %{@pending_key => _} = companion ->
        Map.delete(companion, @pending_key)

      %{"pending_http_followups" => _} = companion ->
        Map.delete(companion, "pending_http_followups")

      other ->
        other
    end)
  end

  defp completed_flights(state) when is_map(state) do
    case Map.get(state, @completed_key) || Map.get(state, to_string(@completed_key)) do
      %MapSet{} = set -> set
      list when is_list(list) -> MapSet.new(list)
      _ -> MapSet.new()
    end
  end

  defp completed_flight?(project_slug, key) do
    project_slug
    |> AgentStore.fetch()
    |> completed_flights()
    |> MapSet.member?(key)
  rescue
    _ -> false
  end

  defp mark_http_completed(state, command) when is_map(state) and is_map(command) do
    Map.put(state, @completed_key, MapSet.put(completed_flights(state), http_flight_key(command)))
  end

  defp ensure_drain_lock_table do
    if :ets.whereis(@drain_lock_table) == :undefined do
      :ets.new(@drain_lock_table, [:named_table, :public, :set, read_concurrency: true])
    end

    :ok
  end

  defp ensure_in_flight_table do
    if :ets.whereis(@in_flight_table) == :undefined do
      :ets.new(@in_flight_table, [:named_table, :public, :set, read_concurrency: true])
    end

    :ok
  end

  defp http_in_flight?(key) do
    ensure_in_flight_table()

    case :ets.lookup(@in_flight_table, key) do
      [{^key, true}] -> true
      _ -> false
    end
  end

  defp mark_http_in_flight(key) do
    ensure_in_flight_table()
    :ets.insert(@in_flight_table, {key, true})
  end

  defp clear_http_in_flight(key) do
    case :ets.whereis(@in_flight_table) do
      :undefined -> :ok
      tid -> :ets.delete(tid, key)
    end
  end

  @spec release_drain_lock(String.t()) :: :ok
  defp release_drain_lock(project_slug) when is_binary(project_slug) do
    case :ets.whereis(@drain_lock_table) do
      :undefined -> :ok
      tid -> :ets.delete(tid, project_slug)
    end

    :ok
  end
end
