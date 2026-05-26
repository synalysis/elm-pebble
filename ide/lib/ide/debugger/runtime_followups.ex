defmodule Ide.Debugger.RuntimeFollowups do
  @moduledoc false

  alias Ide.Debugger.CmdCall
  alias Ide.Debugger.DeviceData
  alias Ide.Debugger.DeviceDataResponses
  alias Ide.Debugger.HttpExecutor
  alias Ide.Debugger.IntrospectAccess
  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.RuntimeModelMessages
  alias Ide.Debugger.Surface
  alias Ide.Debugger.Types

  @type apply_ctx :: %{
          required(:append_event) =>
            (Types.runtime_state(), String.t(), map() -> Types.runtime_state()),
          required(:apply_step_once) =>
            (Types.runtime_state(), Types.surface_target(), String.t(),
             Types.subscription_payload() | map() | nil, String.t(), String.t() ->
               Types.runtime_state()),
          required(:source_root_for_target) => (Types.surface_target() -> String.t()),
          required(:track_http_command) =>
            (Types.runtime_state(), Types.tracked_http_command() -> Types.runtime_state()),
          required(:simulator_settings) => (Types.runtime_state() -> Types.simulator_settings())
        }

  @spec apply_after_step(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          String.t(),
          list(),
          apply_ctx()
        ) :: Types.runtime_state()
  def apply_after_step(state, target, message, message_source, followups, ctx),
    do: apply_runtime(state, target, message, message_source, followups, ctx)

  @spec apply_static_task_after_step(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          Types.subscription_payload(),
          String.t(),
          apply_ctx()
        ) :: Types.runtime_state()
  def apply_static_task_after_step(state, target, message, message_value, message_source, ctx),
    do: apply_static_task(state, target, message, message_value, message_source, ctx)

  defp apply_runtime(state, _target, _message, "runtime_followup", _followups, _ctx),
    do: state

  defp apply_runtime(state, _target, _message, "configuration", _followups, _ctx),
    do: state

  defp apply_runtime(state, target, message, _message_source, followups, ctx)
       when target in [:watch, :companion, :phone] and is_binary(message) and is_list(followups) and
              is_map(ctx) do
    current_ctor = RuntimeModelMessages.wire_constructor(message)
    target_name = ctx.source_root_for_target.(target)

    followups
    |> Enum.filter(&is_map/1)
    |> Enum.filter(fn row ->
      cond do
        shadowed_by_device_data?(state, target, message, row) ->
          false

        is_map(Map.get(row, "command") || Map.get(row, :command)) ->
          true

        true ->
          followup_message = Map.get(row, "message") || Map.get(row, :message)

          is_binary(followup_message) and followup_message != "" and
            followup_message != current_ctor
      end
    end)
    |> Enum.take(5)
    |> Enum.reduce(state, fn row, acc ->
      followup_message = Map.get(row, "message") || Map.get(row, :message)
      package = Map.get(row, "package") || Map.get(row, :package)
      command = Map.get(row, "command") || Map.get(row, :command)

      cond do
        package == "elm/http" and is_map(command) ->
          apply_runtime_http_followup(acc, target, target_name, package, command, followup_message, ctx)

        true ->
          apply_runtime_package_followup(acc, target, target_name, package, row, ctx)
      end
    end)
  end

  defp apply_runtime(state, _target, _message, _message_source, _followups, _ctx),
    do: state

  defp shadowed_by_device_data?(state, target, message, row)
       when is_map(state) and target in [:watch, :companion, :phone] and is_binary(message) and
              is_map(row) do
    package = Map.get(row, "package") || Map.get(row, :package)
    followup_message = Map.get(row, "message") || Map.get(row, :message)

    package == "elm-pebble/elm-watch" and is_binary(followup_message) and
      Enum.any?(DeviceDataResponses.requests_for_surface(state, target, message), fn req ->
        DeviceData.response_message(req) == followup_message or
          RuntimeModelMessages.wire_constructor(DeviceData.response_message(req)) == followup_message
      end)
  end

  defp shadowed_by_device_data?(_state, _target, _message, _row), do: false

  defp apply_static_task(
         state,
         _target,
         _message,
         _message_value,
         "runtime_followup",
         _ctx
       ),
       do: state

  defp apply_static_task(state, target, message, message_value, _message_source, ctx)
       when is_map(state) and target in [:watch, :companion, :phone] and is_binary(message) and
              is_map(ctx) do
    ei = (Surface.from_state(state, target) |> Surface.introspect())
    current_ctor = RuntimeModelMessages.wire_constructor(message)
    target_name = ctx.source_root_for_target.(target)

    ei
    |> static_task_followup_rows(current_ctor)
    |> Enum.take(3)
    |> Enum.reduce(state, fn row, acc ->
      callback = Map.get(row, "callback_constructor")

      with true <- is_binary(callback) and callback != "" and callback != current_ctor,
           {:ok, followup_value} <- static_task_followup_message_value(row, message_value, acc) do
        acc
        |> ctx.append_event.(
          "debugger.package_cmd",
          Ide.Debugger.Types.PackageCmdEventPayload.from_static_task(
            target_name,
            "elm/core",
            callback,
            %{
              "kind" => "cmd.task.perform",
              "task_sources" => Map.get(row, "task_sources", [])
            }
          )
        )
        |> ctx.apply_step_once.(
          target,
          callback,
          followup_value,
          "runtime_followup",
          "runtime_followup"
        )
      else
        _ -> acc
      end
    end)
  end

  defp apply_static_task(state, _target, _message, _message_value, _message_source, _ctx), do: state

  @spec static_task_followup_rows(map(), String.t() | nil) :: [map()]
  defp static_task_followup_rows(ei, current_ctor)
       when is_map(ei) and is_binary(current_ctor) and current_ctor != "" do
    helper_calls =
      ei
      |> Map.get("function_cmd_calls", %{})
      |> case do
        value when is_map(value) -> value
        _ -> %{}
      end

    ei
    |> IntrospectAccess.cmd_calls("update_cmd_calls")
    |> DeviceDataResponses.filter_update_cmd_calls(current_ctor)
    |> Enum.flat_map(fn row ->
      helper_name = Map.get(row, "target") || Map.get(row, "name")

      case Map.get(helper_calls, helper_name) do
        calls when is_list(calls) -> calls
        _ -> []
      end
    end)
    |> Enum.filter(fn row ->
      CmdCall.name?(row, "perform") or CmdCall.target_ends_with?(row, ".perform")
    end)
  end

  defp static_task_followup_rows(_ei, _current_ctor), do: []

  @spec static_task_followup_message_value(map(), Types.subscription_payload(), map()) :: {:ok, map()} | :error
  defp static_task_followup_message_value(row, current_message_value, state)
       when is_map(row) and is_map(state) do
    callback = Map.get(row, "callback_constructor")
    captured_count = Map.get(row, "callback_arg_count", 0)

    with true <- is_binary(callback) and callback != "",
         {:ok, task_value} <- static_task_value(Map.get(row, "task_sources", []), state) do
      captured_args = captured_message_args(current_message_value, captured_count)
      {:ok, %{"ctor" => callback, "args" => captured_args ++ [task_value]}}
    else
      _ -> :error
    end
  end

  defp static_task_followup_message_value(_row, _current_message_value, _state), do: :error

  @spec captured_message_args(Types.subscription_payload(), non_neg_integer()) ::
          [Types.protocol_wire_arg()]
  defp captured_message_args(_message_value, count) when not is_integer(count) or count <= 0,
    do: []

  defp captured_message_args(%{"args" => args}, count) when is_list(args) do
    args
    |> Enum.flat_map(&unwrap_result_payload/1)
    |> Enum.take(count)
  end

  defp captured_message_args(%{args: args}, count) when is_list(args) do
    args
    |> Enum.flat_map(&unwrap_result_payload/1)
    |> Enum.take(count)
  end

  defp captured_message_args(_message_value, _count), do: []

  @spec unwrap_result_payload(Types.subscription_payload()) :: [Types.protocol_wire_arg()]
  defp unwrap_result_payload(%{"ctor" => "Ok", "args" => [value]}), do: [value]
  defp unwrap_result_payload(%{ctor: "Ok", args: [value]}), do: [value]
  defp unwrap_result_payload(value), do: [value]

  @spec static_task_value([String.t()], Types.runtime_state()) ::
          {:ok, Types.static_task_result()} | :error
  defp static_task_value(sources, _state) when is_list(sources) do
    cond do
      "Time.now" in sources and "Time.getZoneName" in sources ->
        {:ok, {static_time_posix(), static_time_zone_name()}}

      "Time.now" in sources ->
        {:ok, static_time_posix()}

      "Time.getZoneName" in sources ->
        {:ok, static_time_zone_name()}

      true ->
        :error
    end
  end

  defp static_task_value(_sources, _state), do: :error

  @spec static_time_posix() :: map()
  defp static_time_posix do
    %{"ctor" => "Posix", "args" => [System.system_time(:millisecond)]}
  end

  @spec static_time_zone_name() :: map()
  defp static_time_zone_name do
    %{"ctor" => "Offset", "args" => [utc_offset_minutes_now()]}
  end

  @spec apply_runtime_http_followup(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          String.t(),
          map(),
          String.t() | nil,
          apply_ctx()
        ) :: Types.runtime_state()
  defp apply_runtime_http_followup(state, target, target_name, package, command, followup_message, ctx)
       when target in [:watch, :companion, :phone] and is_map(command) and is_map(ctx) do
    model = Surface.app_model(Surface.from_state(state, target))
    eval_context = http_eval_context(model, ctx.simulator_settings.(state))

    case HttpExecutor.execute(command, eval_context) do
      {:ok, result} when is_map(result) ->
        response_message = Map.get(result, "message") || followup_message || "elm/http"
        message_value = Map.get(result, "message_value")

        state
        |> ctx.track_http_command.(command)
        |> ctx.append_event.(
          "debugger.package_cmd",
          Ide.Debugger.Types.PackageCmdEventPayload.from_http(
            target_name,
            package,
            response_message,
            http_command_event(command),
            Map.get(result, "response"),
            simulated_http_response?(Map.get(result, "response")),
            followup_message
          )
        )
        |> ctx.apply_step_once.(
          target,
          response_message,
          message_value,
          "runtime_followup",
          "runtime_followup"
        )

      {:error, reason} ->
        ctx.append_event.(
          state,
          "debugger.package_cmd_error",
          Ide.Debugger.Types.PackageCmdErrorEventPayload.from_error(
            target_name,
            package,
            http_command_event(command),
            reason
          )
        )
    end
  end

  defp apply_runtime_http_followup(state, _target, _target_name, _package, _command, _message, _ctx),
    do: state

  @spec apply_runtime_package_followup(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          String.t(),
          map(),
          apply_ctx()
        ) :: Types.runtime_state()
  defp apply_runtime_package_followup(state, target, target_name, package, row, ctx)
       when target in [:watch, :companion, :phone] and is_map(row) do
    case Ide.Debugger.PackageCommandHandler.handle(state, target_name, package, row) do
      {:handled, next_state, event_payload, %{message: message, message_value: message_value}} ->
        next_state
        |> ctx.append_event.(
          "debugger.package_cmd",
          Ide.Debugger.Types.PackageCmdEventPayload.from_handler(event_payload)
        )
        |> ctx.apply_step_once.(
          target,
          message,
          message_value,
          "runtime_followup",
          "runtime_followup"
        )

      {:handled, next_state, event_payload, nil} ->
        ctx.append_event.(
          next_state,
          "debugger.package_cmd",
          Ide.Debugger.Types.PackageCmdEventPayload.from_handler(event_payload)
        )

      :unhandled ->
        followup_message = Map.get(row, "message") || Map.get(row, :message)
        followup_message_value = Map.get(row, "message_value") || Map.get(row, :message_value)

        state
        |> ctx.append_event.(
          "debugger.package_cmd",
          Ide.Debugger.Types.PackageCmdEventPayload.from_followup(
            target_name,
            package,
            followup_message
          )
        )
        |> ctx.apply_step_once.(
          target,
          followup_message,
          followup_message_value,
          "runtime_followup",
          "runtime_followup"
        )
    end
  end

  defp apply_runtime_package_followup(state, _target, _target_name, _package, _row, _ctx), do: state

  @spec utc_offset_minutes_now() :: integer()
  defp utc_offset_minutes_now do
    local_seconds =
      :calendar.local_time()
      |> :calendar.datetime_to_gregorian_seconds()

    utc_seconds =
      :calendar.universal_time()
      |> :calendar.datetime_to_gregorian_seconds()

    div(local_seconds - utc_seconds, 60)
  end

  @spec http_eval_context(Types.execution_model(), Types.simulator_settings()) :: map()
  defp http_eval_context(model, settings) when is_map(model) and is_map(settings) do
    weather = Map.get(settings, "weather")

    extras =
      if is_map(weather) and map_size(weather) > 0,
        do: [simulator_weather: weather],
        else: []

    RuntimeArtifacts.core_ir_eval_context(model, extras)
  end

  defp http_eval_context(_model, _settings), do: %{}

  @spec simulated_http_response?(map() | nil) :: boolean()
  defp simulated_http_response?(%{"status" => 200, "body" => body}) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"current" => _}} -> true
      {:ok, %{"temperature" => _}} -> true
      _ -> false
    end
  end

  defp simulated_http_response?(_response), do: false

  @spec http_command_event(Types.cmd_call()) :: map()
  defp http_command_event(command) when is_map(command) do
    %{
      method: Map.get(command, "method") || Map.get(command, :method),
      url: Map.get(command, "url") || Map.get(command, :url),
      package: Map.get(command, "package") || Map.get(command, :package)
    }
  end

  @spec tracked_http_commands(Types.runtime_state()) :: [Types.tracked_http_command()]
  def tracked_http_commands(state) when is_map(state) do
    case Map.get(state, :companion) do
      %{tracked_http_commands: commands} when is_list(commands) -> commands
      %{"tracked_http_commands" => commands} when is_list(commands) -> commands
      _ -> []
    end
  end

  @spec track_http_command(Types.runtime_state(), Types.tracked_http_command()) ::
          Types.runtime_state()
  def track_http_command(state, %{"kind" => "http"} = command) when is_map(state) do
    key = {Map.get(command, "method"), Map.get(command, "url")}

    tracked =
      state
      |> tracked_http_commands()
      |> Enum.reject(fn existing -> {Map.get(existing, "method"), Map.get(existing, "url")} == key end)

    update_in(state, [:companion], fn companion ->
      companion = if is_map(companion), do: companion, else: %{}
      Map.put(companion, :tracked_http_commands, [command | tracked] |> Enum.take(8))
    end)
  end

  def track_http_command(state, _command), do: state

  @spec reapply_tracked_http_commands(Types.runtime_state(), apply_ctx()) :: Types.runtime_state()
  def reapply_tracked_http_commands(state, ctx) when is_map(state) and is_map(ctx) do
    weather = Map.get(ctx.simulator_settings.(state), "weather")

    if is_map(weather) and map_size(weather) > 0 do
      state
      |> tracked_http_commands()
      |> Enum.reduce(state, fn command, acc ->
        apply_runtime_http_followup(acc, :companion, "companion", "elm/http", command, nil, ctx)
      end)
    else
      state
    end
  end
end
