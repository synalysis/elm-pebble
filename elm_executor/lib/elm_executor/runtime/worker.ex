defmodule ElmExecutor.Runtime.Worker do
  @moduledoc """
  Generic embeddable worker host for compiled elm_executor modules.
  """

  use GenServer
  alias ElmExecutor.Runtime.Scheduler

  @max_scheduler_steps 64

  @type start_opts :: [
          {:module, module()},
          {:request_template, map()},
          {:history_limit, pos_integer()}
        ]

  @spec start_link(start_opts()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @spec dispatch(pid(), String.t()) :: {:ok, map()} | {:error, term()}
  def dispatch(pid, message) when is_binary(message) do
    GenServer.call(pid, {:dispatch, message})
  end

  @spec inject_tick(pid(), map()) :: {:ok, map()} | {:error, term()}
  def inject_tick(pid, payload \\ %{}) when is_map(payload) do
    GenServer.call(pid, {:tick, payload})
  end

  @spec replay_recent(pid(), pos_integer()) :: [map()]
  def replay_recent(pid, count) when is_integer(count) and count > 0 do
    GenServer.call(pid, {:replay_recent, count})
  end

  @spec state(pid()) :: map()
  def state(pid) do
    GenServer.call(pid, :state)
  end

  @impl true
  @spec init(term()) :: term()
  def init(opts) do
    module = Keyword.fetch!(opts, :module)
    request_template = Keyword.get(opts, :request_template, %{})
    history_limit = Keyword.get(opts, :history_limit, 200)

    state = %{
      module: module,
      request_template: request_template,
      current_model: %{"runtime_model" => %{}},
      current_view_tree: %{},
      last_result: nil,
      history_limit: history_limit,
      scheduler: Scheduler.new()
    }

    {:ok, state}
  end

  @impl true
  @spec handle_call(term(), term(), term()) :: term()
  def handle_call({:dispatch, message}, _from, state) do
    scheduler =
      state.scheduler
      |> Scheduler.enqueue("dispatch", message, %{})
      |> run_scheduler(
        state.module,
        state.request_template,
        state.current_model,
        state.current_view_tree
      )

    case List.first(scheduler.history) do
      nil ->
        {:reply, {:error, :dispatch_failed}, state}

      event ->
        next_state = state_from_event(state, scheduler, event)
        {:reply, {:ok, event.payload.result}, next_state}
    end
  end

  def handle_call({:tick, payload}, _from, state) do
    scheduler =
      state.scheduler
      |> Scheduler.enqueue("tick", "Tick", payload)
      |> run_scheduler(
        state.module,
        state.request_template,
        state.current_model,
        state.current_view_tree
      )

    case List.first(scheduler.history) do
      nil ->
        {:reply, {:error, :tick_failed}, state}

      event ->
        next_state = state_from_event(state, scheduler, event)
        {:reply, {:ok, event.payload.result}, next_state}
    end
  end

  def handle_call({:replay_recent, count}, _from, state) do
    replay =
      state.scheduler
      |> Scheduler.replay_recent(count)
      |> Enum.map(fn event ->
        %{seq: event.seq, type: event.type, message: event.message}
      end)

    {:reply, replay, state}
  end

  def handle_call(:state, _from, state), do: {:reply, state, state}

  @spec run_scheduler(term(), term(), term(), term(), term()) :: term()
  defp run_scheduler(scheduler, module, request_template, current_model, current_view_tree) do
    run_scheduler_loop(scheduler, module, request_template, current_model, current_view_tree, 0)
  end

  @spec run_scheduler_loop(term(), term(), term(), term(), term(), term()) :: term()
  defp run_scheduler_loop(
         scheduler,
         _module,
         _request_template,
         _current_model,
         _current_view_tree,
         steps
       )
       when steps >= @max_scheduler_steps do
    scheduler
  end

  defp run_scheduler_loop(
         scheduler,
         module,
         request_template,
         current_model,
         current_view_tree,
         steps
       ) do
    case Scheduler.dequeue(scheduler) do
      {:ok, event, scheduler_after_dequeue} ->
        request =
          request_template
          |> Map.put(:message, event.message)
          |> Map.put(:message_source, Map.get(event.payload, :message_source))
          |> Map.put(:message_value, Map.get(event.payload, :message_value))
          |> Map.put(:current_model, current_model)
          |> Map.put(:current_view_tree, current_view_tree)

        result =
          case module.debugger_execute(request) do
            {:ok, response} -> response
            {:error, reason} -> %{"error" => inspect(reason), "runtime_model" => current_model}
          end

        merged_event = %{event | payload: Map.put(event.payload, :result, result)}

        scheduler =
          scheduler_after_dequeue
          |> Scheduler.record(merged_event)
          |> enqueue_followup_messages(result)

        next_model = extract_runtime_model(result, current_model)
        next_view_tree = extract_view_tree(result, current_view_tree)

        run_scheduler_loop(
          scheduler,
          module,
          request_template,
          next_model,
          next_view_tree,
          steps + 1
        )

      :empty ->
        scheduler
    end
  end

  @spec enqueue_followup_messages(term(), term()) :: term()
  defp enqueue_followup_messages(scheduler, result) when is_map(result) do
    followups =
      case Map.get(result, :followup_messages) || Map.get(result, "followup_messages") do
        rows when is_list(rows) -> rows
        _ -> []
      end

    Enum.reduce(followups, scheduler, fn row, acc ->
      message = Map.get(row, "message") || Map.get(row, :message)
      source = Map.get(row, "source") || Map.get(row, :source) || "runtime_followup"

      if is_binary(message) and String.trim(message) != "" do
        payload =
          %{message_source: source}
          |> Map.put(
            :message_value,
            Map.get(row, "message_value") || Map.get(row, :message_value)
          )

        Scheduler.enqueue(acc, "runtime_followup", message, payload)
      else
        acc
      end
    end)
  end

  defp enqueue_followup_messages(scheduler, _result), do: scheduler

  @spec extract_runtime_model(term(), term()) :: term()
  defp extract_runtime_model(result, fallback) when is_map(result) do
    case Map.get(result, :model_patch) || Map.get(result, "model_patch") do
      patch when is_map(patch) ->
        case Map.get(patch, "runtime_model") || Map.get(patch, :runtime_model) do
          model when is_map(model) and map_size(model) > 0 -> %{"runtime_model" => model}
          _ -> fallback
        end

      _ ->
        fallback
    end
  end

  defp extract_runtime_model(_result, fallback), do: fallback

  @spec extract_view_tree(term(), term()) :: term()
  defp extract_view_tree(result, fallback) when is_map(result) do
    case Map.get(result, :view_tree) || Map.get(result, "view_tree") do
      tree when is_map(tree) -> tree
      _ -> fallback
    end
  end

  defp extract_view_tree(_result, fallback), do: fallback

  @spec state_from_event(term(), term(), term()) :: term()
  defp state_from_event(state, scheduler, event) do
    result = event.payload.result
    next_model = Map.get(result, :model_patch, %{})["runtime_model"] || %{}
    next_view_tree = Map.get(result, :view_tree) || %{}

    next_state = %{
      state
      | current_model: %{"runtime_model" => next_model},
        current_view_tree: next_view_tree,
        last_result: result,
        scheduler: scheduler
    }

    trim_history(next_state)
  end

  @spec trim_history(term()) :: term()
  defp trim_history(state) do
    history_limit = state.history_limit
    scheduler = state.scheduler
    trimmed = %{scheduler | history: Enum.take(scheduler.history, history_limit)}
    %{state | scheduler: trimmed}
  end

  @impl true
  @spec handle_info(term(), term()) :: term()
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  @spec terminate(term(), term()) :: term()
  def terminate(_reason, _state), do: :ok

  @impl true
  @spec code_change(term(), term(), term()) :: term()
  def code_change(_old_vsn, state, _extra), do: {:ok, state}
end
