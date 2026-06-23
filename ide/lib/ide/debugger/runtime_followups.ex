defmodule Ide.Debugger.RuntimeFollowups do
  @moduledoc false

  alias Ide.Debugger.CompanionBridge.Runtime, as: CompanionBridgeRuntime
  alias Ide.Debugger.DeviceData
  alias Ide.Debugger.DeviceDataResponses
  alias Ide.Debugger.DeviceRequest
  alias Ide.Debugger.TimelineMessage
  alias Ide.Debugger.HttpExecutor
  alias Ide.Debugger.PendingHttpFollowups
  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.RuntimeModelMessages
  alias Ide.Debugger.SimulatorWatchDelivery
  alias Ide.Debugger.Surface
  alias Ide.Debugger.SurfaceTargets
  alias Ide.Debugger.Types

  @type apply_ctx :: %{
          required(:append_event) => (Types.runtime_state(),
                                      String.t(),
                                      Types.debugger_timeline_payload() ->
                                        Types.runtime_state()),
          required(:append_debugger_event) => (Types.runtime_state(),
                                               String.t(),
                                               Types.surface_target(),
                                               String.t(),
                                               String.t()
                                               | nil,
                                               Types.timeline_step_message_value() ->
                                                 Types.runtime_state()),
          required(:apply_step_once) => (Types.runtime_state(),
                                         Types.surface_target(),
                                         String.t(),
                                         Types.subscription_payload()
                                         | nil,
                                         String.t(),
                                         String.t() ->
                                           Types.runtime_state()),
          required(:source_root_for_target) => (Types.surface_target() -> String.t()),
          required(:track_http_command) => (Types.runtime_state(), Types.tracked_http_command() ->
                                              Types.runtime_state()),
          required(:simulator_settings) => (Types.runtime_state() -> Types.simulator_settings()),
          optional(:companion_bridge) => CompanionBridgeRuntime.ctx()
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

  @doc false
  @spec executor_followups?([Types.runtime_followup_row()]) :: boolean()
  def executor_followups?(followups) when is_list(followups), do: followups != []
  def executor_followups?(_followups), do: false

  @doc false
  @spec companion_bridge_followups?([Types.runtime_followup_row()]) :: boolean()
  def companion_bridge_followups?(followups) when is_list(followups) do
    Enum.any?(followups, &companion_bridge_followup?/1)
  end

  def companion_bridge_followups?(_followups), do: false

  @doc false
  @spec geolocation_followups?([Types.runtime_followup_row()]) :: boolean()
  def geolocation_followups?(followups) when is_list(followups) do
    Enum.any?(followups, &geolocation_followup_row?/1)
  end

  def geolocation_followups?(_followups), do: false

  @doc false
  @spec covered_device_response_ctors([Types.runtime_followup_row()]) :: [String.t()]
  def covered_device_response_ctors(followups) when is_list(followups) do
    followups
    |> Enum.flat_map(fn row ->
      if device_followup_row?(row) do
        case followup_response_ctor(row) do
          ctor when is_binary(ctor) and ctor != "" -> [ctor]
          _ -> []
        end
      else
        []
      end
    end)
    |> Enum.uniq()
  end

  def covered_device_response_ctors(_followups), do: []

  @doc false
  @spec covered_companion_bridge_requests([Types.runtime_followup_row()]) ::
          [Types.companion_bridge_request()]
  def covered_companion_bridge_requests(followups) when is_list(followups) do
    followups
    |> Enum.filter(&companion_bridge_followup_row?/1)
    |> Enum.map(fn row -> Map.get(row, "command") || Map.get(row, :command) end)
    |> Enum.map(&Ide.Debugger.CompanionBridgeRequest.from_bridge_command/1)
    |> Enum.reject(&is_nil/1)
  end

  def covered_companion_bridge_requests(_followups), do: []

  @doc false
  @spec companion_bridge_request_covered?(
          Types.companion_bridge_request(),
          [Types.companion_bridge_request()]
        ) :: boolean()
  def companion_bridge_request_covered?(request, covered)
      when is_map(request) and is_list(covered) do
    Enum.any?(covered, &same_bridge_request?(request, &1))
  end

  def companion_bridge_request_covered?(_request, _covered), do: false

  @spec same_bridge_request?(
          Types.companion_bridge_request(),
          Types.companion_bridge_request()
        ) :: boolean()
  defp same_bridge_request?(left, right) when is_map(left) and is_map(right) do
    Map.get(left, :api) == Map.get(right, :api) and Map.get(left, :op) == Map.get(right, :op) and
      bridge_request_key(left) == bridge_request_key(right)
  end

  defp same_bridge_request?(_left, _right), do: false

  @spec bridge_request_key(Types.companion_bridge_request()) :: String.t()
  defp bridge_request_key(request) when is_map(request) do
    request
    |> Map.get(:key)
    |> case do
      key when is_binary(key) -> key
      _ -> ""
    end
  end

  @doc false
  @spec geolocation_followup_row?(Types.runtime_followup_row()) :: boolean()
  def geolocation_followup_row?(row) when is_map(row) do
    command = Map.get(row, "command") || Map.get(row, :command) || %{}

    case Map.get(command, "api") || Map.get(command, :api) do
      "geolocation" -> true
      _ -> false
    end
  end

  def geolocation_followup_row?(_row), do: false

  @doc false
  @spec device_followup_row?(Types.runtime_followup_row()) :: boolean()
  def device_followup_row?(row) when is_map(row) do
    source = Map.get(row, "source") || Map.get(row, :source)
    command = Map.get(row, "command") || Map.get(row, :command)

    source == "device_command" or
      (is_map(command) and
         command
         |> Map.get("kind", Map.get(command, :kind))
         |> to_string()
         |> String.starts_with?("cmd.device."))
  end

  def device_followup_row?(_row), do: false

  defp followup_response_ctor(row) when is_map(row) do
    message = Map.get(row, "message") || Map.get(row, :message)

    cond do
      is_binary(message) and message != "" ->
        RuntimeModelMessages.wire_constructor(message) || message

      true ->
        row
        |> Map.get("message_value", Map.get(row, :message_value))
        |> case do
          %{"ctor" => ctor} when is_binary(ctor) -> ctor
          %{ctor: ctor} when is_binary(ctor) -> ctor
          _ -> nil
        end
    end
  end

  @doc false
  @spec companion_bridge_followup_row?(Types.runtime_followup_row()) :: boolean()
  def companion_bridge_followup_row?(row), do: companion_bridge_followup?(row)

  defp apply_runtime(state, _target, _message, "runtime_followup", _followups, _ctx),
    do: state

  defp apply_runtime(state, _target, _message, "configuration", _followups, _ctx),
    do: state

  defp apply_runtime(state, target, message, message_source, followups, ctx)
       when target in [:watch, :companion, :phone] and is_binary(message) and is_list(followups) and
              is_map(ctx) do
    current_ctor = RuntimeModelMessages.wire_constructor(message)
    target_name = ctx.source_root_for_target.(target)

    mapped_followups = Enum.filter(followups, &is_map/1)
    {bridge_followups, followups} = Enum.split_with(mapped_followups, &companion_bridge_followup?/1)

    state =
      case Map.get(ctx, :companion_bridge) do
        %{} = bridge_ctx ->
          CompanionBridgeRuntime.apply_followup_rows(
            state,
            target,
            companion_bridge_source(message_source),
            bridge_followups,
            bridge_ctx
          )

        _ ->
          state
      end

    {protocol_followups, runtime_followups} =
      case message_source do
        src when src in ["http", "runtime_followup"] ->
          Enum.split_with(followups, &protocol_events_followup?/1)

        _ ->
          {[], Enum.reject(followups, &protocol_events_followup?/1)}
      end

    state =
      Enum.reduce(protocol_followups, state, fn row, acc ->
        apply_protocol_runtime_followup(acc, row, ctx)
      end)

    runtime_followups
    |> Enum.filter(fn row ->
      cond do
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
        package == "elm/http" and is_map(command) and PendingHttpFollowups.async?() ->
          acc
          |> track_http_command(command)
          |> PendingHttpFollowups.enqueue(
            target,
            target_name,
            package,
            command,
            followup_message
          )

        package == "elm/http" and is_map(command) ->
          apply_runtime_http_followup(
            acc,
            target,
            target_name,
            package,
            command,
            followup_message,
            ctx
          )

        true ->
          apply_runtime_package_followup(acc, target, target_name, package, row, message, ctx)
      end
    end)
  end

  defp apply_runtime(state, _target, _message, _message_source, _followups, _ctx),
    do: state

  @spec protocol_events_followup?(Types.runtime_followup_row()) :: boolean()
  defp protocol_events_followup?(row) when is_map(row) do
    package = Map.get(row, "package") || Map.get(row, :package)
    package == "companion-protocol"
  end

  defp protocol_events_followup?(_row), do: false

  @spec apply_protocol_runtime_followup(Types.runtime_state(), Types.runtime_followup_row(), apply_ctx()) ::
          Types.runtime_state()
  defp apply_protocol_runtime_followup(state, row, ctx) when is_map(state) and is_map(row) and is_map(ctx) do
    command = Map.get(row, "command") || Map.get(row, :command) || %{}
    message = Map.get(row, "message") || Map.get(row, :message)
    message_value = Map.get(row, "message_value") || Map.get(row, :message_value)
    to = Map.get(command, "to") || Map.get(command, :to) || "watch"
    target = SurfaceTargets.normalize(to)
    target_name = ctx.source_root_for_target.(target)

    {step_message, step_value} =
      if is_binary(message) and message != "" do
        {message, message_value}
      else
        resolve_runtime_followup_step(state, target, "", message, message_value, row)
      end

    state
    |> ctx.append_event.(
      "debugger.package_cmd",
      Ide.Debugger.Types.PackageCmdEventPayload.from_followup(
        target_name,
        "companion-protocol",
        TimelineMessage.format(step_message, step_value)
      )
    )
    |> maybe_apply_runtime_followup_step(target, step_message, step_value, ctx)
  end

  @spec maybe_apply_runtime_followup_step(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          Types.subscription_payload() | map() | nil,
          apply_ctx()
        ) :: Types.runtime_state()
  defp maybe_apply_runtime_followup_step(state, target, step_message, message_value, ctx)
       when is_map(state) and target in [:watch, :companion, :phone] and is_map(ctx) do
    if is_binary(step_message) and String.trim(step_message) != "" do
      ctx.apply_step_once.(
        state,
        target,
        step_message,
        message_value,
        "runtime_followup",
        "runtime_followup"
      )
    else
      state
    end
  end

  defp maybe_apply_runtime_followup_step(state, _target, _step_message, _message_value, _ctx),
    do: state

  @spec companion_bridge_followup?(Types.runtime_followup_row()) :: boolean()
  defp companion_bridge_followup?(row) when is_map(row) do
    source = Map.get(row, "source") || Map.get(row, :source)
    package = Map.get(row, "package") || Map.get(row, :package)
    command = Map.get(row, "command") || Map.get(row, :command)

    source == "companion_bridge_command" or
      (package == "pebble/companion" and is_map(command) and
         Map.get(command, "kind") == "cmd.companion.bridge")
  end

  defp companion_bridge_followup?(_row), do: false

  @spec companion_bridge_source(String.t()) :: String.t()
  defp companion_bridge_source("init"), do: "init_companion_bridge"
  defp companion_bridge_source(source) when source in ["runtime_followup", "companion_bridge_command"], do: source
  defp companion_bridge_source(_source), do: "companion_bridge_command"

  @spec execute_http_command(
          Types.runtime_state(),
          Types.surface_target(),
          Types.cmd_call(),
          apply_ctx()
        ) :: Ide.Debugger.HttpExecutor.result()
  def execute_http_command(state, target, command, ctx)
      when is_map(state) and target in [:watch, :companion, :phone] and is_map(command) and
             is_map(ctx) do
    model = Surface.app_model(Surface.from_state(state, target))
    eval_context = http_eval_context(model, ctx.simulator_settings.(state))
    HttpExecutor.execute(command, eval_context)
  end

  @spec apply_http_executor_result(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          String.t(),
          map(),
          String.t() | nil,
          {:ok, map()} | {:error, term()},
          apply_ctx()
        ) :: Types.runtime_state()
  def apply_http_executor_result(
        state,
        target,
        target_name,
        package,
        command,
        followup_message,
        result,
        ctx
      )
      when target in [:watch, :companion, :phone] and is_map(command) and is_map(ctx) do
    case result do
      {:ok, payload} when is_map(payload) ->
        response_message =
          followup_message ||
            Map.get(payload, "message") ||
            Map.get(payload, :message) ||
            "elm/http"

        message_value = Map.get(payload, "message_value") || Map.get(payload, :message_value)

        state
        |> ctx.track_http_command.(command)
        |> ctx.append_event.(
          "debugger.package_cmd",
          Ide.Debugger.Types.PackageCmdEventPayload.from_http(
            target_name,
            package,
            response_message,
            http_command_event(command),
            Map.get(payload, "response"),
            simulated_http_response?(Map.get(payload, "response")),
            followup_message
          )
        )
        |> ctx.apply_step_once.(
          target,
          response_message,
          message_value,
          "http",
          "runtime_followup"
        )
        |> deliver_http_phone_to_watch_followups(
          target,
          response_message,
          message_value,
          ctx
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

  @phone_to_watch_weather_messages ~w(ProvideTemperature ProvideCondition)

  @spec deliver_http_phone_to_watch_followups(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          Types.protocol_message_wire_value() | nil,
          apply_ctx()
        ) :: Types.runtime_state()
  defp deliver_http_phone_to_watch_followups(
         state,
         target,
         response_message,
         message_value,
         ctx
       )
       when target in [:companion, :phone] and is_map(state) and is_map(ctx) do
    with true <- weather_received_message?(response_message, message_value),
         settings when is_map(settings) <- ctx.simulator_settings.(state) do
      weather = Map.get(settings, "weather") || %{}

      Enum.reduce(@phone_to_watch_weather_messages, state, fn message_name, acc ->
        case SimulatorWatchDelivery.weather_message_value(message_name, weather) do
          nil ->
            acc

          wire_value ->
            step_message = SimulatorWatchDelivery.weather_step_message(message_name, weather)

            acc
            |> ctx.apply_step_once.(
              :watch,
              step_message,
              wire_value,
              "http",
              "runtime_followup"
            )
        end
      end)
    else
      _ -> state
    end
  end

  defp deliver_http_phone_to_watch_followups(state, _target, _response_message, _message_value, _ctx),
    do: state

  defp weather_received_message?(response_message, message_value) do
    ctor =
      response_message
      |> to_string()
      |> RuntimeModelMessages.wire_constructor()

    match?(%{"ctor" => "WeatherReceived", "args" => [%{"ctor" => "Ok", "args" => [_]}]}, message_value) or
      ctor == "WeatherReceived"
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
  defp apply_runtime_http_followup(
         state,
         target,
         target_name,
         package,
         command,
         followup_message,
         ctx
       )
       when target in [:watch, :companion, :phone] and is_map(command) and is_map(ctx) do
    result = execute_http_command(state, target, command, ctx)

    apply_http_executor_result(
      state,
      target,
      target_name,
      package,
      command,
      followup_message,
      result,
      ctx
    )
  end

  defp apply_runtime_http_followup(
         state,
         _target,
         _target_name,
         _package,
         _command,
         _message,
         _ctx
       ),
       do: state

  @spec apply_runtime_package_followup(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          String.t(),
          map(),
          String.t(),
          apply_ctx()
        ) :: Types.runtime_state()
  defp apply_runtime_package_followup(
         state,
         target,
         target_name,
         package,
         row,
         parent_message,
         ctx
       )
       when target in [:watch, :companion, :phone] and is_map(row) and is_binary(parent_message) do
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

        {step_message, message_value} =
          resolve_runtime_followup_step(
            state,
            target,
            parent_message,
            followup_message,
            followup_message_value,
            row
          )

        state
        |> ctx.append_event.(
          "debugger.package_cmd",
          Ide.Debugger.Types.PackageCmdEventPayload.from_followup(
            target_name,
            package,
            TimelineMessage.format(step_message, message_value)
          )
        )
        |> maybe_apply_runtime_followup_step(
          target,
          step_message,
          message_value,
          ctx
        )
    end
  end

  defp apply_runtime_package_followup(
         state,
         _target,
         _target_name,
         _package,
         _row,
         _parent_message,
         _ctx
       ),
       do: state

  @spec resolve_runtime_followup_step(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          String.t() | nil,
          Types.subscription_payload() | map() | nil,
          map()
        ) :: {String.t(), map() | nil}
  defp resolve_runtime_followup_step(
         state,
         target,
         parent_message,
         followup_message,
         followup_message_value,
         row
       )
       when is_map(state) and target in [:watch, :companion, :phone] and is_binary(parent_message) and
              is_map(row) do
    cond do
      is_map(followup_message_value) ->
        value =
          refresh_device_followup_value(
            state,
            target,
            parent_message,
            followup_message,
            followup_message_value,
            row
          )

        {RuntimeModelMessages.wire_constructor(followup_message || "") || followup_message || "",
         value}

      is_binary(followup_message) and followup_message != "" ->
        case TimelineMessage.message_value_for_step(followup_message) do
          {message, %{} = value} ->
            {message, value}

          {message, nil} ->
            case device_command_wire_value(state, target, parent_message, message, row) ||
                   synthesized_device_wire_value(state, target, parent_message, message) do
              %{} = value -> {message, value}
              _ -> {message, nil}
            end
        end

      true ->
        {"", nil}
    end
  end

  defp resolve_runtime_followup_step(
         _state,
         _target,
         _parent_message,
         _followup_message,
         _followup_message_value,
         _row
       ),
       do: {"", nil}

  @spec refresh_device_followup_value(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          String.t() | nil,
          Types.subscription_payload() | map(),
          Types.runtime_followup_row()
        ) :: Types.subscription_payload() | map()
  defp refresh_device_followup_value(
         state,
         target,
         parent_message,
         followup_message,
         default_value,
         row
       )
       when is_map(state) and is_binary(parent_message) and is_map(row) do
    ctor =
      followup_message
      |> case do
        message when is_binary(message) and message != "" -> message
        _ -> Map.get(default_value, "ctor") || Map.get(default_value, :ctor)
      end

    case device_command_wire_value(state, target, parent_message, ctor, row) do
      %{} = value -> value
      _ -> default_value
    end
  end

  defp refresh_device_followup_value(_state, _target, _parent_message, _followup_message, default_value, _row),
    do: default_value

  @spec device_command_wire_value(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          String.t(),
          Types.runtime_followup_row()
        ) :: Types.protocol_ctor_value() | nil
  defp device_command_wire_value(state, target, parent_message, followup_message, row)
       when is_map(state) and is_binary(parent_message) and is_binary(followup_message) and
              is_map(row) do
    command = Map.get(row, "command") || Map.get(row, :command)

    with %{"kind" => kind} when is_binary(kind) <- command,
         true <- String.starts_with?(kind, "cmd.device.") do
      model = Surface.app_model(Surface.from_state(state, target))

      row
      |> device_request_row(followup_message)
      |> DeviceRequest.from_cmd_call()
      |> List.first()
      |> case do
        nil ->
          nil

        req ->
          req
          |> DeviceData.finalize_request(model, parent_message)
          |> DeviceData.response_wire_value()
      end
    else
      _ -> nil
    end
  end

  defp device_command_wire_value(_state, _target, _parent_message, _followup_message, _row),
    do: nil

  @spec device_request_row(Types.runtime_followup_row(), String.t()) :: Types.cmd_call()
  defp device_request_row(row, followup_message) when is_map(row) do
    command = Map.get(row, "command") || Map.get(row, :command) || %{}
    kind = Map.get(command, "kind") || Map.get(command, :kind) || ""

    %{
      "name" => device_command_name(kind, command),
      "target" => device_command_target(kind, command),
      "callback_constructor" => followup_message,
      "branch_constructor" => Map.get(row, "branch_constructor"),
      "task_sources" => Map.get(row, "task_sources", [])
    }
  end

  defp device_command_name("cmd.device." <> kind, _command), do: device_command_name_for_kind(kind)

  defp device_command_name(kind, command) do
    Map.get(command, "name") || Map.get(command, :name) ||
      device_command_name_for_kind(kind)
  end

  defp device_command_name_for_kind("current_date_time"), do: "getCurrentDateTime"
  defp device_command_name_for_kind("current_time_string"), do: "getCurrentTimeString"
  defp device_command_name_for_kind("battery_level"), do: "getBatteryLevel"
  defp device_command_name_for_kind("connection_status"), do: "getConnectionStatus"
  defp device_command_name_for_kind("clock_style_24h"), do: "getClockStyle24h"
  defp device_command_name_for_kind("timezone_is_set"), do: "getTimezoneIsSet"
  defp device_command_name_for_kind("timezone"), do: "getTimezone"
  defp device_command_name_for_kind("watch_model"), do: "getModel"
  defp device_command_name_for_kind("watch_color"), do: "getColor"
  defp device_command_name_for_kind("firmware_version"), do: "getFirmwareVersion"
  defp device_command_name_for_kind("health_value"), do: "value"
  defp device_command_name_for_kind("health_supported"), do: "supported"
  defp device_command_name_for_kind("health_sum_today"), do: "sumToday"
  defp device_command_name_for_kind("health_sum"), do: "sum"
  defp device_command_name_for_kind("health_accessible"), do: "accessible"
  defp device_command_name_for_kind(_), do: ""

  defp device_command_target("cmd.device." <> kind, command),
    do: device_command_target_for_kind(kind, command)

  defp device_command_target(kind, command) do
    device_command_target_for_kind(kind, command)
  end

  defp device_command_target_for_kind(kind, command) when is_binary(kind) do
    cond do
      kind in health_device_kinds() ->
        "Pebble.Health"

      kind in pebble_cmd_device_kinds() ->
        "Pebble.Cmd"

      true ->
        Map.get(command, "target") || Map.get(command, :target) || "Pebble.Cmd"
    end
  end

  defp health_device_kinds do
    ~w(health_value health_supported health_sum_today health_sum health_accessible)
  end

  defp pebble_cmd_device_kinds do
    ~w(current_date_time current_time_string battery_level connection_status clock_style_24h
       timezone_is_set timezone watch_model watch_color firmware_version)
  end

  @spec synthesized_device_wire_value(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          String.t()
        ) :: Types.protocol_ctor_value() | nil
  defp synthesized_device_wire_value(state, target, parent_message, ctor)
       when is_map(state) and target in [:watch, :companion, :phone] and is_binary(parent_message) and
              is_binary(ctor) and ctor != "" do
    from_parent =
      state
      |> DeviceDataResponses.requests_for_surface(target, parent_message)
      |> Enum.find_value(fn req ->
        if req.response_message == ctor, do: DeviceData.response_wire_value(req)
      end)

    from_parent || callback_wire_from_surface(state, target, ctor, parent_message)
  end

  defp synthesized_device_wire_value(_state, _target, _parent_message, _ctor), do: nil

  @spec callback_wire_from_surface(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          String.t()
        ) :: Types.protocol_ctor_value() | nil
  defp callback_wire_from_surface(state, target, ctor, current_message)
       when is_map(state) and target in [:watch, :companion, :phone] and is_binary(ctor) and
              ctor != "" do
    surface = Surface.from_state(state, target)
    model = Surface.app_model(surface)
    introspect = Surface.introspect(surface)

    DeviceData.response_wire_for_callback(introspect, model, ctor, current_message)
  end

  defp callback_wire_from_surface(_state, _target, _ctor, _current_message), do: nil

  @spec http_eval_context(Types.execution_model(), Types.simulator_settings()) ::
          Types.eval_context()
  defp http_eval_context(model, settings) when is_map(model) and is_map(settings) do
    weather = Map.get(settings, "weather")

    extras =
      if settings["use_simulator_weather"] != false and is_map(weather) and map_size(weather) > 0,
        do: [simulator_weather: weather],
        else: []

    RuntimeArtifacts.eval_context(model, extras)
  end

  defp http_eval_context(_model, _settings), do: %{}

  @spec simulated_http_response?(Types.HttpSimulatedResponse.wire_map() | nil) :: boolean()
  defp simulated_http_response?(%{"status" => 200, "body" => body}) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"current" => _}} -> true
      {:ok, %{"temperature" => _}} -> true
      _ -> false
    end
  end

  defp simulated_http_response?(_response), do: false

  @spec http_command_event(Types.cmd_call()) :: Types.wire_map()
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
      |> Enum.reject(fn existing ->
        {Map.get(existing, "method"), Map.get(existing, "url")} == key
      end)

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
