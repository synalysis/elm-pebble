defmodule Ide.Debugger.PendingHttpFollowups do
  @moduledoc """
  Runs deferred `elm/http` follow-ups outside the debugger Agent lock.

  Requests are started concurrently (like Elm `Cmd.batch`). Each response is applied
  via `update` in completion order, not request order.
  """

  alias Ide.Debugger.AgentHosts
  alias Ide.Debugger.AgentSession
  alias Ide.Debugger.AgentStore
  alias Ide.Debugger.RuntimeBackgroundDrains
  alias Ide.Debugger.RuntimeBackgroundWork
  alias Ide.Debugger.RuntimeFollowups
  alias Ide.Debugger.SurfaceTargets
  alias Ide.Debugger.Types

  @pending_key :pending_http_followups

  @spec async?() :: boolean()
  def async? do
    Application.get_env(:ide, :debugger_async_http_followups, true)
  end

  @spec maybe_schedule_drain(String.t(), map()) :: :ok
  def maybe_schedule_drain(project_slug, state)
      when is_binary(project_slug) and is_map(state) do
    if async?() do
      items = pending(state)

      if items != [] do
        {:ok, _} =
          AgentSession.mutate(project_slug, fn st ->
            put_pending(st, [])
          end)

        AgentSession.with_hosts(fn hosts ->
          ctx = hosts |> AgentHosts.contexts() |> Map.fetch!(:runtime_followups)
          Enum.each(items, &launch_flight(project_slug, &1, ctx))
        end)
      end
    end

    :ok
  end

  @spec pending(map()) :: [map()]
  def pending(state) when is_map(state) do
    case Map.get(state, @pending_key) || Map.get(state, to_string(@pending_key)) do
      commands when is_list(commands) -> commands
      _ -> legacy_companion_pending(state)
    end
  end

  @spec enqueue(
          map(),
          Types.surface_target(),
          String.t(),
          String.t(),
          map(),
          String.t() | nil
        ) :: map()
  def enqueue(state, target, target_name, package, command, followup_message)
      when is_map(state) and target in [:watch, :companion, :phone] and is_binary(target_name) and
             is_binary(package) and is_map(command) do
    item = %{
      "target" => Atom.to_string(target),
      "target_name" => target_name,
      "package" => package,
      "command" => command,
      "followup_message" => followup_message
    }

    Map.update(state, @pending_key, [item], &(&1 ++ [item]))
  end

  @spec launch_flight(String.t(), map(), RuntimeFollowups.apply_ctx()) :: :ok
  def launch_flight(project_slug, item, ctx)
      when is_binary(project_slug) and is_map(item) and is_map(ctx) do
    RuntimeBackgroundWork.spawn(project_slug, fn -> run_flight(project_slug, item, ctx) end)
  end

  @spec run_flight(String.t(), map(), RuntimeFollowups.apply_ctx()) :: :ok
  def run_flight(project_slug, item, ctx)
      when is_binary(project_slug) and is_map(item) and is_map(ctx) do
    {target, target_name, package, command, followup_message} = flight_fields(item)

    result =
      AgentStore.fetch(project_slug)
      |> execute_flight_http(target, command, ctx)

    {:ok, state} =
      AgentSession.mutate(project_slug, fn state ->
        RuntimeFollowups.apply_http_executor_result(
          state,
          target,
          target_name,
          package,
          command,
          followup_message,
          result,
          ctx
        )
      end)

    RuntimeBackgroundDrains.schedule_all(project_slug, state)
    :ok
  end

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
      %{@pending_key => _} = companion -> Map.delete(companion, @pending_key)
      %{"pending_http_followups" => _} = companion -> Map.delete(companion, "pending_http_followups")
      other -> other
    end)
  end
end
