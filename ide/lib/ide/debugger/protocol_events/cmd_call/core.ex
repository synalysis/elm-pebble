defmodule Ide.Debugger.ProtocolEvents.CmdCall.Core do
  @moduledoc false

  @protocol_subscription_wrapper_ctors ~w(FromWatch FromPhone)

  alias Ide.Debugger.CompanionBridge
  alias Ide.Debugger.Geolocation
  alias Ide.Debugger.ProtocolResolutionCtx
  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.SimulatorSettings, as: DebuggerSimulatorSettings
  alias Ide.Debugger.Types
  alias Ide.Debugger.WireValues
  alias Ide.Projects

  alias Ide.Debugger.ProtocolEvents
  alias Ide.Debugger.ProtocolEvents.Subscription

  @type resolution_ctx :: ProtocolResolutionCtx.t()
  @type ctx :: ProtocolEvents.ctx()

  def events_from_cmd_call(state, target_surface, cmd_call, model, message_value, ctx)

  def events_from_cmd_call(state, :watch, cmd_call, model, message_value, ctx)
      when is_map(cmd_call) and is_map(ctx) do
    name = (Map.get(cmd_call, "name") || Map.get(cmd_call, :name) || "") |> to_string()
    target = (Map.get(cmd_call, "target") || Map.get(cmd_call, :target) || "") |> to_string()

    {message, protocol_value} =
      protocol_message_payload_for_cmd_call(
        state,
        cmd_call,
        model,
        :watch_to_phone,
        message_value,
        ctx
      )

    if name == "sendWatchToPhone" or String.ends_with?(target, ".sendWatchToPhone") do
      Ide.Debugger.Types.ProtocolTxRxPayload.tx_rx_events(
        "watch",
        "companion",
        message,
        "init_cmd",
        protocol_value
      )
    else
      []
    end
  end

  def events_from_cmd_call(state, target_surface, cmd_call, model, message_value, ctx)
      when target_surface in [:companion, :phone] and is_map(cmd_call) and is_map(ctx) do
    name = (Map.get(cmd_call, "name") || Map.get(cmd_call, :name) || "") |> to_string()
    target = (Map.get(cmd_call, "target") || Map.get(cmd_call, :target) || "") |> to_string()

    {message, protocol_value} =
      protocol_message_payload_for_cmd_call(
        state,
        cmd_call,
        model,
        :phone_to_watch,
        message_value,
        ctx
      )

    if name == "sendPhoneToWatch" or String.ends_with?(target, ".sendPhoneToWatch") do
      Ide.Debugger.Types.ProtocolTxRxPayload.tx_rx_events(
        "companion",
        "watch",
        message,
        "protocol_cmd",
        protocol_value
      )
    else
      []
    end
  end

  def events_from_cmd_call(_state, _surface, _cmd_call, _model, _message_value, _ctx), do: []

  @spec events_for_model_commands(
          Types.runtime_state(),
          Types.app_model(),
          Types.surface_target(),
          String.t(),
          Types.subscription_payload(),
          ctx()
        ) :: [Types.protocol_timeline_event()]
  def events_for_model_commands(state, model, target, message, message_value, ctx)
      when is_map(state) and is_map(model) and target in [:watch, :companion, :phone] and
             is_binary(message) and is_map(ctx) do
    ctx.cmd_calls_for_message.(state, target, message)
    |> Enum.flat_map(&events_from_cmd_call(state, target, &1, model, message_value, ctx))
  end

  def events_for_model_commands(_state, _model, _target, _message, _message_value, _ctx),
    do: []

  @spec protocol_message_payload_for_cmd_call(
          Types.runtime_state(),
          Types.cmd_call(),
          Types.app_model(),
          :watch_to_phone | :phone_to_watch,
          Types.subscription_payload(),
          ctx()
        ) ::
          {String.t() | nil, Types.protocol_message_wire_value()}
  defp protocol_message_payload_for_cmd_call(
         state,
         cmd_call,
         model,
         direction,
         message_value,
         events_ctx
       )

  defp protocol_message_payload_for_cmd_call(
         state,
         cmd_call,
         model,
         direction,
         message_value,
         events_ctx
       )
       when is_map(cmd_call) and direction in [:watch_to_phone, :phone_to_watch] and
              is_map(events_ctx) do
    case protocol_schema_from_state_or_model(state, model, events_ctx) do
      {:ok, schema} ->
        resolution_ctx =
          ProtocolResolutionCtx.new(
            direction: direction,
            protocol_ctor: protocol_message_ctor_name(cmd_call),
            runtime_model: RuntimeArtifacts.inner_runtime_model(model),
            simulator_settings: events_ctx.simulator_settings_from_state.(state),
            message_value: message_value
          )

        protocol_message_payload_from_cmd_call(cmd_call, schema, direction, resolution_ctx)

      {:error, _} ->
        protocol_message_payload_from_arg_values(cmd_call, direction)
    end
  end

  defp protocol_message_payload_for_cmd_call(
         _state,
         _cmd_call,
         _model,
         _direction,
         _message_value,
         _events_ctx
       ),
       do: {nil, nil}

  @spec protocol_message_payload_from_cmd_call(
          Types.cmd_call(),
          Types.protocol_schema(),
          :watch_to_phone | :phone_to_watch,
          ProtocolResolutionCtx.t()
        ) :: {String.t() | nil, Types.protocol_message_wire_value()}
  defp protocol_message_payload_from_cmd_call(cmd_call, schema, direction, ctx)
       when is_map(cmd_call) and is_map(schema) and
              direction in [:watch_to_phone, :phone_to_watch] and
              is_map(ctx) do
    callback =
      Map.get(cmd_call, "callback_constructor") || Map.get(cmd_call, :callback_constructor)

    case resolve_protocol_message_from_cmd_call(cmd_call, schema, direction, ctx) do
      {message, protocol_value}
      when is_binary(message) and message != "" and is_map(protocol_value) ->
        wrap_watch_to_phone_protocol_payload(direction, message, protocol_value)

      _ ->
        case protocol_message_from_schema(schema, direction, callback) do
          message when is_binary(message) and message != "" ->
            wrap_watch_to_phone_protocol_payload(
              direction,
              message,
              protocol_message_value_from_schema(schema, direction, callback)
            )

          _ ->
            protocol_message_payload_from_arg_values(cmd_call, direction)
        end
    end
  end

  @spec wrap_watch_to_phone_protocol_payload(
          :watch_to_phone | :phone_to_watch,
          String.t(),
          Types.protocol_message_wire_value()
        ) :: {String.t(), Types.protocol_message_wire_value()}
  defp wrap_watch_to_phone_protocol_payload(:watch_to_phone, message, protocol_value)
       when is_binary(message) do
    inner_value = normalize_elmc_wire_ctor(protocol_value)

    inner_message =
      case inner_value do
        %{"ctor" => ctor, "args" => args} when is_binary(ctor) ->
          protocol_message_display(ctor, List.wrap(args))

        _ ->
          message
      end

    wire_value = %{
      "ctor" => "FromWatch",
      "args" => [%{"ctor" => "Ok", "args" => [inner_value]}]
    }

    if String.starts_with?(message, "FromWatch") do
      {inner_message |> then(&("FromWatch (Ok #{Subscription.parenthesize_elm_arg(&1)})")), wire_value}
    else
      {"FromWatch (Ok #{Subscription.parenthesize_elm_arg(inner_message)})", wire_value}
    end
  end

  defp wrap_watch_to_phone_protocol_payload(_direction, message, protocol_value),
    do: {message, protocol_value}

  @spec protocol_message_payload_from_arg_values(
          Types.cmd_call(),
          :watch_to_phone | :phone_to_watch | nil
        ) :: {String.t() | nil, Types.protocol_message_wire_value()}
  defp protocol_message_payload_from_arg_values(cmd_call, direction)

  defp protocol_message_payload_from_arg_values(cmd_call, direction) when is_map(cmd_call) do
    case protocol_ctor_from_cmd_call(cmd_call) do
      {:ok, ctor, inner_args} when is_binary(ctor) ->
        args = inner_args |> List.wrap() |> Enum.map(&normalize_elmc_wire_ctor/1)
        inner_value = %{"ctor" => ctor, "args" => args}
        inner_message = protocol_message_display(ctor, args)

        if direction == :watch_to_phone do
          wrap_watch_to_phone_protocol_payload(direction, inner_message, inner_value)
        else
          {inner_message, inner_value}
        end

      _ ->
        callback =
          Map.get(cmd_call, "callback_constructor") || Map.get(cmd_call, :callback_constructor)

        if is_binary(callback) and callback != "", do: {callback, nil}, else: {nil, nil}
    end
  end

  @spec protocol_message_ctor_name(Types.cmd_call()) :: String.t() | nil
  defp protocol_message_ctor_name(cmd_call) when is_map(cmd_call) do
    case protocol_ctor_from_cmd_call(cmd_call) do
      {:ok, ctor, _} when is_binary(ctor) -> ctor
      _ -> Map.get(cmd_call, "callback_constructor") || Map.get(cmd_call, :callback_constructor)
    end
  end

  @spec resolve_protocol_message_from_cmd_call(
          Types.cmd_call(),
          Types.protocol_schema(),
          :watch_to_phone | :phone_to_watch,
          ProtocolResolutionCtx.t()
        ) :: {String.t(), Types.protocol_ctor_value()} | :error
  defp resolve_protocol_message_from_cmd_call(
         cmd_call,
         schema,
         direction,
         %ProtocolResolutionCtx{} = ctx
       )
       when is_map(cmd_call) and is_map(schema) and
              direction in [:watch_to_phone, :phone_to_watch] do
    with {:ok, ctor, inner_args} <- protocol_ctor_from_cmd_call(cmd_call),
         %{fields: fields} <- protocol_schema_message(schema, direction, ctor),
         ctx = ProtocolResolutionCtx.with_message_resolution(ctx, schema, ctor, fields),
         {:ok, resolved_args} <- resolve_protocol_ctor_args(inner_args, fields, schema, ctx) do
      message_value = %{"ctor" => ctor, "args" => resolved_args}
      {protocol_message_display(ctor, resolved_args), message_value}
    else
      _ -> :error
    end
  end

  defp resolve_protocol_message_from_cmd_call(_cmd_call, _schema, _direction, _ctx), do: :error

  @spec protocol_ctor_from_cmd_call(Types.cmd_call()) :: {:ok, String.t(), list()} | :error
  defp protocol_ctor_from_cmd_call(cmd_call) when is_map(cmd_call) do
    case raw_protocol_ctor_from_cmd_call(cmd_call) do
      {:ok, ctor, args} when is_binary(ctor) ->
        unwrap_protocol_wire_ctor({:ok, ctor, List.wrap(args)})

      :error ->
        :error
    end
  end

  @spec raw_protocol_ctor_from_cmd_call(Types.cmd_call()) :: {:ok, String.t(), list()} | :error
  defp raw_protocol_ctor_from_cmd_call(%{"arg_values" => [first | _]}) when is_map(first) do
    ctor = Map.get(first, "$ctor") || Map.get(first, "ctor")
    args = Map.get(first, "$args") || Map.get(first, "args") || []

    if is_binary(ctor) and ctor != "" do
      {:ok, ctor, List.wrap(args)}
    else
      :error
    end
  end

  defp raw_protocol_ctor_from_cmd_call(%{arg_values: [first | _]}) when is_map(first) do
    raw_protocol_ctor_from_cmd_call(%{"arg_values" => [first]})
  end

  defp raw_protocol_ctor_from_cmd_call(_cmd_call), do: :error

  @spec unwrap_protocol_wire_ctor({:ok, String.t(), list()}) :: {:ok, String.t(), list()} | :error
  defp unwrap_protocol_wire_ctor({:ok, ctor, args})
       when ctor in @protocol_subscription_wrapper_ctors and is_list(args) do
    case List.wrap(args) do
      [%{"ctor" => result, "args" => [inner | _]} | _]
      when result in ["Ok", "Err"] and is_map(inner) ->
        inner_ctor = Map.get(inner, "ctor") || Map.get(inner, "$ctor")
        inner_args = Map.get(inner, "args") || Map.get(inner, "$args") || []

        if is_binary(inner_ctor) and inner_ctor != "" do
          unwrap_protocol_wire_ctor({:ok, inner_ctor, List.wrap(inner_args)})
        else
          {:ok, ctor, args}
        end

      [%{ctor: result, args: [inner | _]} | _]
      when result in ["Ok", "Err"] and is_map(inner) ->
        inner_ctor = Map.get(inner, :ctor) || Map.get(inner, "ctor")
        inner_args = Map.get(inner, :args) || Map.get(inner, "args") || []

        if is_binary(inner_ctor) and inner_ctor != "" do
          unwrap_protocol_wire_ctor({:ok, inner_ctor, List.wrap(inner_args)})
        else
          {:ok, ctor, args}
        end

      _ ->
        {:ok, ctor, args}
    end
  end

  defp unwrap_protocol_wire_ctor(other), do: other

  @spec resolve_protocol_ctor_args(
          [Types.protocol_wire_arg()],
          [Ide.Debugger.Protocol.Schema.field()],
          Types.protocol_schema(),
          ProtocolResolutionCtx.t()
        ) ::
          {:ok, [Types.protocol_wire_arg()]} | :error
  defp resolve_protocol_ctor_args(inner_args, fields, schema, %ProtocolResolutionCtx{} = ctx)
       when is_list(inner_args) and is_list(fields) and is_map(schema) do
    resolved =
      inner_args
      |> Enum.with_index()
      |> Enum.map(fn {arg, index} ->
        field = Enum.at(fields, index) || %{}
        wire_type = Map.get(field, :wire_type)

        resolve_protocol_ctor_arg(
          arg,
          wire_type,
          schema,
          ProtocolResolutionCtx.with_arg_index(ctx, index)
        )
      end)

    if Enum.any?(resolved, &(not is_nil(&1))) do
      {:ok, resolved}
    else
      :error
    end
  end

  defp resolve_protocol_ctor_args(_inner_args, _fields, _schema, _ctx), do: :error

  @spec resolve_protocol_ctor_arg(
          Types.protocol_wire_arg(),
          Types.protocol_wire_type(),
          Types.protocol_schema(),
          ProtocolResolutionCtx.t()
        ) ::
          Types.protocol_wire_arg() | nil
  defp resolve_protocol_ctor_arg(arg, wire_type, schema, ctx) do
    value =
      WireValues.coalesce([
        resolve_protocol_arg_expr(arg, ctx),
        resolve_protocol_arg_fallback(wire_type, schema, ctx),
        simulator_settings_wire_value(wire_type, ctx)
      ])

    normalize_protocol_resolved_value(wire_type, schema, value)
  end

  @spec normalize_protocol_resolved_value(
          Types.protocol_wire_type(),
          Types.protocol_schema(),
          Types.protocol_wire_arg()
        ) :: Types.protocol_wire_arg() | nil
  defp normalize_protocol_resolved_value({:union, "Temperature"} = wire_type, schema, value) do
    normalize_temperature_value(value, schema, wire_type)
  end

  defp normalize_protocol_resolved_value({:enum, type} = wire_type, schema, value)
       when is_map(schema) and is_binary(type) do
    normalize_protocol_wire_value(schema, value, wire_type)
  end

  defp normalize_protocol_resolved_value({:union, type}, schema, value)
       when is_binary(type) and is_map(value) do
    case value do
      %{"ctor" => ctor, "args" => args} when is_binary(ctor) and is_list(args) ->
        %{
          "ctor" => ctor,
          "args" => Enum.map(args, &normalize_protocol_resolved_value({:union, type}, schema, &1))
        }

      _ ->
        value
    end
  end

  defp normalize_protocol_resolved_value(_wire_type, _schema, value), do: value

  @spec normalize_temperature_value(
          Types.protocol_wire_arg(),
          Types.protocol_schema(),
          Types.protocol_wire_type()
        ) :: Types.protocol_wire_arg() | nil
  defp normalize_temperature_value(
         %{"ctor" => "Celsius", "args" => [arg | _]},
         _schema,
         _wire_type
       ) do
    case DebuggerSimulatorSettings.temperature_scalar(arg) do
      nil -> %{"ctor" => "Celsius", "args" => [0]}
      int -> %{"ctor" => "Celsius", "args" => [int]}
    end
  end

  defp normalize_temperature_value(
         %{"ctor" => "Fahrenheit", "args" => [arg | _]},
         _schema,
         _wire_type
       ) do
    case DebuggerSimulatorSettings.temperature_scalar(arg) do
      nil -> %{"ctor" => "Fahrenheit", "args" => [0]}
      int -> %{"ctor" => "Fahrenheit", "args" => [int]}
    end
  end

  defp normalize_temperature_value(value, _schema, _wire_type)
       when is_integer(value) or is_float(value) do
    %{"ctor" => "Celsius", "args" => [DebuggerSimulatorSettings.temperature_scalar(value)]}
  end

  defp normalize_temperature_value(%{} = record, schema, wire_type) do
    case Map.get(record, "temperature") do
      temp when is_integer(temp) or is_float(temp) ->
        normalize_temperature_value(temp, schema, wire_type)

      _ ->
        record
    end
  end

  defp normalize_temperature_value(value, _schema, _wire_type), do: value

  @spec resolve_protocol_arg_expr(Types.protocol_wire_arg(), resolution_ctx()) ::
          Types.protocol_wire_arg() | nil
  defp resolve_protocol_arg_expr(%{"$field" => field, "$on" => on_expr}, ctx)
       when is_binary(field) and is_map(on_expr) and is_map(ctx) do
    case resolve_protocol_binding_record(on_expr, ctx) do
      record when is_map(record) -> Map.get(record, field)
      _ -> nil
    end
  end

  defp resolve_protocol_arg_expr(%{"$var" => name}, ctx) when is_binary(name) and is_map(ctx) do
    runtime_model = Map.get(ctx, :runtime_model) || %{}

    cond do
      Map.has_key?(runtime_model, name) ->
        Map.get(runtime_model, name)

      true ->
        case Map.get(protocol_message_var_bindings(ctx), name) do
          %{} = record ->
            record

          _ ->
            nil
        end
    end
  end

  defp resolve_protocol_arg_expr(%{"$call" => call, "$args" => args}, ctx)
       when is_binary(call) and is_list(args) and is_map(ctx) do
    resolved_args = Enum.map(args, &resolve_protocol_arg_expr(&1, ctx))

    if round_call?(call) do
      case resolved_args do
        [num | _] when is_integer(num) -> num
        [num | _] when is_float(num) -> DebuggerSimulatorSettings.temperature_scalar(num)
        _ -> nil
      end
    else
      nil
    end
  end

  defp resolve_protocol_arg_expr(value, _ctx)
       when is_integer(value) or is_boolean(value) or is_binary(value),
       do: value

  defp resolve_protocol_arg_expr(%{"$ctor" => ctor, "$args" => args}, ctx)
       when is_binary(ctor) and is_list(args) and is_map(ctx) do
    %{
      "ctor" => ctor,
      "args" =>
        args
        |> Enum.map(&resolve_protocol_arg_expr(&1, ctx))
        |> Enum.reject(&is_nil/1)
    }
  end

  defp resolve_protocol_arg_expr(%{"$opaque" => true, "op" => "field_access"}, _ctx), do: nil
  defp resolve_protocol_arg_expr(_arg, _ctx), do: nil

  @spec resolve_protocol_binding_record(Types.protocol_wire_arg(), resolution_ctx()) ::
          Types.protocol_wire_arg() | nil
  defp resolve_protocol_binding_record(%{"$var" => name}, ctx)
       when is_binary(name) and is_map(ctx) do
    case Map.get(protocol_message_var_bindings(ctx), name) do
      %{} = record ->
        record

      _ ->
        protocol_binding_record_from_runtime_model(Map.get(ctx, :runtime_model))
    end
  end

  defp resolve_protocol_binding_record(_expr, _ctx), do: nil

  @spec protocol_message_var_bindings(resolution_ctx()) :: Types.protocol_var_bindings()
  defp protocol_message_var_bindings(ctx) when is_map(ctx) do
    case Map.get(ctx, :message_value) do
      %{"ctor" => ctor, "args" => [inner | _]} when is_binary(ctor) and is_map(inner) ->
        case protocol_ok_inner_record(inner) do
          %{"ctor" => "Current", "args" => [info | _]} = current when is_map(info) ->
            %{"info" => CompanionBridge.weather_info(info), "current" => current}

          %{} = record ->
            binding_name = protocol_ok_payload_binding_name(ctor)

            if is_binary(binding_name) and binding_name != "" do
              %{binding_name => record}
            else
              %{}
            end

          _ ->
            protocol_connectivity_record(inner)
            |> case do
              %{} = record -> %{"connectivity" => record}
              _ -> %{}
            end
        end

      _ ->
        %{}
    end
  end

  @spec protocol_ok_payload_binding_name(String.t()) :: String.t() | nil
  defp protocol_ok_payload_binding_name(ctor) when is_binary(ctor) do
    case String.replace_suffix(ctor, "Received", "") do
      "" ->
        nil

      <<first::utf8, rest::binary>> ->
        String.downcase(<<first::utf8>>) <> rest
    end
  end

  @spec round_call?(String.t()) :: boolean()
  defp round_call?(call) when is_binary(call) do
    String.ends_with?(call, ".round") or call == "round" or call == "Basics.round"
  end

  @spec protocol_binding_record_from_runtime_model(Types.inner_runtime_model() | nil) ::
          Types.protocol_binding_record() | nil
  defp protocol_binding_record_from_runtime_model(%{} = runtime_model) do
    %{
      "percent" => Map.get(runtime_model, "batteryPercent"),
      "charging" => Map.get(runtime_model, "charging"),
      "online" => Map.get(runtime_model, "online"),
      "locale" => Map.get(runtime_model, "locale"),
      "notificationsEnabled" => Map.get(runtime_model, "notificationsEnabled"),
      "quietHours" => Map.get(runtime_model, "quietHours")
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
    |> case do
      %{} = empty when map_size(empty) == 0 -> nil
      record -> record
    end
  end

  defp protocol_binding_record_from_runtime_model(_runtime_model), do: nil

  defp protocol_update_payload_record(%{"ctor" => _ctor, "args" => [inner | _]})
       when is_map(inner) do
    case protocol_ok_inner_record(inner) do
      %{} = record -> record
      _ -> protocol_connectivity_record(inner)
    end
  end

  defp protocol_update_payload_record(%{ctor: ctor, args: [inner | _]}) when is_map(inner) do
    protocol_update_payload_record(%{"ctor" => ctor, "args" => [inner]})
  end

  defp protocol_update_payload_record(_message_value), do: nil

  @spec protocol_connectivity_record(Types.subscription_payload()) ::
          Types.protocol_binding_record() | nil
  defp protocol_connectivity_record(%{"ctor" => "Online"}), do: %{"online" => true}
  defp protocol_connectivity_record(%{"ctor" => "Offline"}), do: %{"online" => false}
  defp protocol_connectivity_record(%{ctor: "Online"}), do: %{"online" => true}
  defp protocol_connectivity_record(%{ctor: "Offline"}), do: %{"online" => false}
  defp protocol_connectivity_record(_inner), do: nil

  @spec protocol_ok_inner_record(Types.subscription_payload()) ::
          Types.protocol_binding_record() | nil
  defp protocol_ok_inner_record(%{"ctor" => "Ok", "args" => [value | _]}) when is_map(value),
    do: value

  defp protocol_ok_inner_record(%{ctor: "Ok", args: [value | _]}) when is_map(value), do: value

  defp protocol_ok_inner_record(%{"ctor" => ctor, "args" => _})
       when ctor in ["Online", "Offline"],
       do: nil

  defp protocol_ok_inner_record(%{ctor: ctor, args: _}) when ctor in ["Online", "Offline"],
    do: nil

  defp protocol_ok_inner_record(value) when is_map(value), do: value

  @spec resolve_protocol_arg_fallback(
          Types.protocol_wire_type(),
          Types.protocol_schema(),
          resolution_ctx()
        ) :: Types.protocol_wire_arg() | nil
  defp resolve_protocol_arg_fallback(wire_type, schema, ctx)
       when is_map(schema) and is_map(ctx) do
    record =
      protocol_update_payload_record(Map.get(ctx, :message_value)) ||
        protocol_binding_record_from_runtime_model(Map.get(ctx, :runtime_model)) ||
        %{}

    value =
      case wire_type do
        :int ->
          WireValues.map_get_first_present(record, [
            "percent",
            "batteryPercent",
            "battery_percent"
          ])

        :bool ->
          protocol_bool_fallback_value(ctx, record)

        :string ->
          Map.get(record, "locale")

        {:enum, type} ->
          protocol_default_value_term(schema, {:enum, type})

        {:union, type} ->
          protocol_default_value_term(schema, {:union, type})

        _ ->
          nil
      end

    WireValues.coalesce([
      value,
      runtime_model_wire_value(wire_type, ctx)
    ])
  end

  defp resolve_protocol_arg_fallback(_wire_type, _schema, _ctx), do: nil

  @spec runtime_model_wire_value(Types.protocol_wire_type(), resolution_ctx()) ::
          Types.wire_input() | nil
  defp runtime_model_wire_value(:int, %{runtime_model: %{} = runtime_model} = ctx) do
    keys =
      case Map.get(ctx, :protocol_ctor) do
        "ProvidePosition" -> provide_position_runtime_model_keys(Map.get(ctx, :arg_index))
        _ -> ["batteryPercent", "percent", "battery_percent"]
      end

    WireValues.map_get_first_present(runtime_model, keys)
  end

  defp runtime_model_wire_value(:bool, ctx) do
    protocol_bool_fallback_value(ctx, Map.get(ctx, :runtime_model) || %{})
  end

  defp runtime_model_wire_value(:string, %{runtime_model: %{} = runtime_model}) do
    Map.get(runtime_model, "locale")
  end

  defp runtime_model_wire_value(_wire_type, _ctx), do: nil

  @spec provide_position_runtime_model_keys(non_neg_integer()) :: [String.t()]
  defp provide_position_runtime_model_keys(0), do: ["latitudeE6"]
  defp provide_position_runtime_model_keys(1), do: ["longitudeE6"]
  defp provide_position_runtime_model_keys(2), do: ["accuracyM"]
  defp provide_position_runtime_model_keys(_), do: []

  @spec simulator_settings_wire_value(Types.protocol_wire_type(), resolution_ctx()) ::
          Types.wire_input() | nil
  defp simulator_settings_wire_value(:int, ctx) when is_map(ctx) do
    case Map.get(ctx, :protocol_ctor) do
      "ProvidePosition" ->
        Geolocation.simulator_wire_int(ctx)

      _ ->
        case Map.get(ctx, :simulator_settings) do
          %{} = settings -> Map.get(settings, "battery_percent")
          _ -> nil
        end
    end
  end

  defp simulator_settings_wire_value(:bool, ctx) do
    protocol_bool_simulator_value(ctx)
  end

  defp simulator_settings_wire_value(:string, %{simulator_settings: %{} = settings}) do
    Map.get(settings, "locale")
  end

  defp simulator_settings_wire_value({:union, "Temperature"}, %{simulator_settings: settings})
       when is_map(settings) do
    case DebuggerSimulatorSettings.temperature_celsius(settings["weather"] || %{}) do
      nil -> nil
      temp -> %{"ctor" => "Celsius", "args" => [temp]}
    end
  end

  defp simulator_settings_wire_value({:enum, "WeatherCondition"}, %{simulator_settings: settings})
       when is_map(settings) do
    weather_condition_from_settings(settings)
  end

  defp simulator_settings_wire_value(_wire_type, _ctx), do: nil

  @spec weather_condition_from_settings(Types.simulator_settings()) :: Types.protocol_ctor_value()
  def weather_condition_from_settings(settings) when is_map(settings) do
    weather = settings["weather"] || %{}

    key =
      (Map.get(weather, "condition") || Map.get(weather, :condition) || "clear")
      |> to_string()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "")

    ctor =
      case key do
        "clear" -> "Clear"
        "cloudy" -> "Cloudy"
        "fog" -> "Fog"
        "drizzle" -> "Drizzle"
        "rain" -> "Rain"
        "snow" -> "Snow"
        "showers" -> "Showers"
        "storm" -> "Storm"
        _ -> "UnknownWeather"
      end

    %{"ctor" => ctor, "args" => []}
  end

  @spec protocol_bool_fallback_value(resolution_ctx(), Types.protocol_binding_record()) ::
          boolean() | nil
  defp protocol_bool_fallback_value(ctx, record) when is_map(ctx) and is_map(record) do
    ctor = Map.get(ctx, :protocol_ctor)

    keys =
      case ctor do
        "ProvideConnectivity" -> ["online"]
        "ProvideBattery" -> ["charging"]
        "ProvideNotifications" -> ["notificationsEnabled", "quietHours"]
        _ -> ["online", "charging", "notificationsEnabled", "quietHours"]
      end

    WireValues.map_get_first_present(record, keys)
  end

  defp protocol_bool_fallback_value(_ctx, _record), do: nil

  @spec protocol_bool_simulator_value(resolution_ctx()) :: boolean() | nil
  defp protocol_bool_simulator_value(%{
         protocol_ctor: "ProvideConnectivity",
         simulator_settings: settings
       })
       when is_map(settings),
       do: Map.get(settings, "network_online")

  defp protocol_bool_simulator_value(%{
         protocol_ctor: "ProvideBattery",
         simulator_settings: settings
       })
       when is_map(settings),
       do: Map.get(settings, "charging")

  defp protocol_bool_simulator_value(_ctx), do: nil

  @spec protocol_schema_from_state_or_model(Types.runtime_state(), Types.app_model(), ctx()) ::
          {:ok, Types.protocol_schema()} | {:error, Types.protocol_error()}
  def protocol_schema_from_state_or_model(state, model, events_ctx) do
    case project_schema(state, events_ctx) do
      {:ok, schema} -> {:ok, schema}
      {:error, _} -> protocol_schema_from_model(model)
    end
  end

  @spec project_schema(Types.runtime_state(), ctx()) ::
          {:ok, Types.protocol_schema()} | {:error, Types.protocol_error()}
  def project_schema(state, events_ctx) when is_map(state) and is_map(events_ctx) do
    with session_key when is_binary(session_key) <- events_ctx.session_key_from_state.(state),
         %{} = project <- Projects.get_project_by_scope_key(session_key),
         workspace_root <- Projects.project_workspace_path(project),
         protocol_types <- Path.join(workspace_root, "protocol/src/Companion/Types.elm"),
         true <- File.exists?(protocol_types),
         {:ok, source} <- File.read(protocol_types) do
      Ide.CompanionProtocolGenerator.schema_from_source(source)
    else
      _ -> {:error, :missing_project_protocol}
    end
  rescue
    DBConnection.OwnershipError ->
      {:error, :repo_unavailable}

    error in [RuntimeError] ->
      case Exception.message(error) do
        "could not lookup Ecto repo " <> _ -> {:error, :repo_unavailable}
        _ -> reraise error, __STACKTRACE__
      end
  end

  @spec protocol_schema_from_model(Types.app_model()) ::
          {:ok, Types.protocol_schema()} | {:error, Types.protocol_error()}
  defp protocol_schema_from_model(_model) do
    path =
      Path.expand(
        "../../priv/internal_packages/companion-protocol/src/Companion/Types.elm",
        __DIR__
      )

    with {:ok, source} <- File.read(path) do
      Ide.CompanionProtocolGenerator.schema_from_source(source)
    end
  end

  @spec protocol_message_from_schema(
          Types.protocol_schema(),
          :watch_to_phone | :phone_to_watch,
          String.t()
        ) ::
          String.t() | nil
  defp protocol_message_from_schema(schema, direction, callback) when is_map(schema) do
    messages =
      case direction do
        :watch_to_phone -> Map.get(schema, :watch_to_phone, [])
        :phone_to_watch -> Map.get(schema, :phone_to_watch, [])
      end

    Enum.find_value(messages, fn
      %{name: ^callback, fields: fields} when is_binary(callback) ->
        args =
          fields
          |> List.wrap()
          |> Enum.map(&protocol_default_value(schema, Map.get(&1, :wire_type)))
          |> Enum.map(&Subscription.parenthesize_elm_arg/1)

        case args do
          [] -> callback
          _ -> callback <> " " <> Enum.join(args, " ")
        end

      _ ->
        nil
    end)
  end

  @spec protocol_message_value_from_schema(
          Types.protocol_schema(),
          :watch_to_phone | :phone_to_watch,
          String.t()
        ) ::
          Types.protocol_ctor_value() | nil
  defp protocol_message_value_from_schema(schema, direction, callback)
       when is_map(schema) and is_binary(callback) and callback != "" do
    messages =
      case direction do
        :watch_to_phone -> Map.get(schema, :watch_to_phone, [])
        :phone_to_watch -> Map.get(schema, :phone_to_watch, [])
      end

    Enum.find_value(messages, fn
      %{name: ^callback, fields: fields} ->
        args =
          fields
          |> List.wrap()
          |> Enum.map(&protocol_default_value_term(schema, Map.get(&1, :wire_type)))

        %{"ctor" => callback, "args" => args}

      _ ->
        nil
    end)
  end

  defp protocol_message_value_from_schema(_schema, _direction, _callback), do: nil

  @spec protocol_default_value(Types.protocol_schema(), Types.protocol_wire_type()) :: String.t()
  defp protocol_default_value(_schema, :int), do: "0"
  defp protocol_default_value(_schema, :bool), do: "True"
  defp protocol_default_value(_schema, :string), do: inspect("debugger response")

  defp protocol_default_value(schema, {:enum, type}) when is_map(schema) and is_binary(type) do
    schema
    |> Map.get(:enums, %{})
    |> Map.get(type, [])
    |> List.first()
    |> case do
      value when is_binary(value) and value != "" -> value
      _ -> "Unknown"
    end
  end

  defp protocol_default_value(schema, {:union, type}) when is_map(schema) and is_binary(type) do
    schema
    |> Map.get(:payload_unions, %{})
    |> Map.get(type, [])
    |> List.first()
    |> case do
      %{name: ctor, args: args} when is_binary(ctor) and is_list(args) ->
        rendered_args =
          args
          |> Enum.map(&protocol_default_value(schema, protocol_wire_type_for_type(schema, &1)))
          |> Enum.join(" ")

        if rendered_args == "", do: ctor, else: "#{ctor} #{rendered_args}"

      _ ->
        "Unknown"
    end
  end

  defp protocol_default_value(_schema, _wire_type), do: "0"

  @spec protocol_default_value_term(Types.protocol_schema(), Types.protocol_wire_type()) ::
          integer() | boolean() | String.t() | Types.protocol_ctor_value()
  defp protocol_default_value_term(_schema, :int), do: 0
  defp protocol_default_value_term(_schema, :bool), do: true
  defp protocol_default_value_term(_schema, :string), do: "debugger response"

  defp protocol_default_value_term(schema, {:enum, type})
       when is_map(schema) and is_binary(type) do
    schema
    |> Map.get(:enums, %{})
    |> Map.get(type, [])
    |> List.first()
    |> case do
      value when is_binary(value) and value != "" -> %{"ctor" => value, "args" => []}
      _ -> %{"ctor" => "Unknown", "args" => []}
    end
  end

  defp protocol_default_value_term(schema, {:union, type})
       when is_map(schema) and is_binary(type) do
    schema
    |> Map.get(:payload_unions, %{})
    |> Map.get(type, [])
    |> List.first()
    |> case do
      %{name: ctor, args: args} when is_binary(ctor) and is_list(args) ->
        %{
          "ctor" => ctor,
          "args" =>
            Enum.map(
              args,
              &protocol_default_value_term(schema, protocol_wire_type_for_type(schema, &1))
            )
        }

      _ ->
        %{"ctor" => "Unknown", "args" => []}
    end
  end

  defp protocol_default_value_term(_schema, _wire_type), do: 0

  @spec protocol_wire_type_for_type(Types.protocol_schema(), String.t()) ::
          Types.protocol_wire_type()
  defp protocol_wire_type_for_type(_schema, "Int"), do: :int
  defp protocol_wire_type_for_type(_schema, "Bool"), do: :bool
  defp protocol_wire_type_for_type(_schema, "String"), do: :string

  defp protocol_wire_type_for_type(schema, type) when is_map(schema) and is_binary(type) do
    cond do
      Map.has_key?(Map.get(schema, :enums, %{}), type) -> {:enum, type}
      Map.has_key?(Map.get(schema, :payload_unions, %{}), type) -> {:union, type}
      true -> :int
    end
  end

  @spec normalize_from_schema(
          [Types.protocol_timeline_event()],
          Types.runtime_state(),
          ctx()
        ) :: [Types.protocol_timeline_event()]
  def normalize_from_schema(protocol_events, state, events_ctx)
      when is_list(protocol_events) and is_map(state) and is_map(events_ctx) do
    case project_schema(state, events_ctx) do
      {:ok, schema} ->
        Enum.map(protocol_events, &normalize_protocol_event_from_schema(&1, schema))

      {:error, _} ->
        protocol_events
    end
  end

  def normalize_from_schema(protocol_events, _state, _events_ctx), do: protocol_events

  @spec normalize_protocol_event_from_schema(
          Types.protocol_timeline_event(),
          Types.protocol_schema()
        ) :: Types.protocol_timeline_event()
  defp normalize_protocol_event_from_schema(event, schema)
       when is_map(event) and is_map(schema) do
    type = Map.get(event, :type) || Map.get(event, "type")
    payload = Map.get(event, :payload) || Map.get(event, "payload")

    if is_binary(type) and is_map(payload) do
      normalized_payload = normalize_protocol_payload_from_schema(payload, schema)
      %{type: type, payload: normalized_payload}
    else
      event
    end
  end

  defp normalize_protocol_event_from_schema(event, _schema), do: event

  @spec normalize_protocol_payload_from_schema(
          Types.protocol_tx_rx_payload(),
          Types.protocol_schema()
        ) :: Types.protocol_tx_rx_payload()
  defp normalize_protocol_payload_from_schema(payload, schema)
       when is_map(payload) and is_map(schema) do
    from = Map.get(payload, :from) || Map.get(payload, "from")
    to = Map.get(payload, :to) || Map.get(payload, "to")
    message = Map.get(payload, :message) || Map.get(payload, "message")
    message_value = Map.get(payload, :message_value) || Map.get(payload, "message_value")

    direction =
      cond do
        from == "watch" and to in ["companion", "phone"] -> :watch_to_phone
        from in ["companion", "phone"] and to == "watch" -> :phone_to_watch
        true -> nil
      end

    case normalize_protocol_message_value_from_schema(schema, direction, message_value, message) do
      {normalized_message, normalized_value} ->
        payload
        |> Map.put(:message, normalized_message)
        |> Map.put(:message_value, normalized_value)

      :error ->
        payload
    end
  end

  @spec normalize_protocol_message_value_from_schema(
          Types.protocol_schema(),
          :watch_to_phone | :phone_to_watch | nil,
          Types.protocol_wire_arg(),
          Types.protocol_wire_arg()
        ) :: {String.t(), Types.protocol_ctor_value()} | :error
  def normalize_protocol_message_value_from_schema(schema, :watch_to_phone, message_value, _message)
      when is_map(schema) and is_map(message_value) do
    case watch_to_phone_tag_value_wire(message_value) do
      {:ok, tag, value} -> decode_watch_to_phone_tag_value(schema, tag, value)
      :error -> :error
    end
  end

  def normalize_protocol_message_value_from_schema(schema, direction, message_value, message)
      when direction in [:watch_to_phone, :phone_to_watch] and is_map(schema) do
    ctor = protocol_message_ctor(message_value) || message_constructor(message)

    with ctor when is_binary(ctor) and ctor != "" <- ctor,
         %{fields: fields} <- protocol_schema_message(schema, direction, ctor),
         args <- protocol_message_args(message_value, length(fields)) do
      normalized_args =
        fields
        |> Enum.zip(args)
        |> Enum.map(fn {field, value} ->
          normalize_protocol_wire_value(schema, value, Map.get(field, :wire_type))
        end)

      normalized_value = %{"ctor" => ctor, "args" => normalized_args}
      {protocol_message_display(ctor, normalized_args), normalized_value}
    else
      _ -> :error
    end
  end

  def normalize_protocol_message_value_from_schema(
        _schema,
        _direction,
        _message_value,
        _message
      ),
      do: :error

  @spec watch_to_phone_tag_value_wire(Types.protocol_wire_arg()) ::
          {:ok, integer(), integer()} | :error
  defp watch_to_phone_tag_value_wire(%{"tag" => tag, "value" => value})
       when is_integer(tag) and is_integer(value),
       do: {:ok, tag, value}

  defp watch_to_phone_tag_value_wire(%{tag: tag, value: value})
       when is_integer(tag) and is_integer(value),
       do: {:ok, tag, value}

  defp watch_to_phone_tag_value_wire(_wire), do: :error

  @spec decode_watch_to_phone_tag_value(Types.protocol_schema(), integer(), integer()) ::
          {String.t(), Types.protocol_ctor_value()} | :error
  defp decode_watch_to_phone_tag_value(schema, tag, value) when is_map(schema) do
    case Enum.find(Map.get(schema, :watch_to_phone, []), &(Map.get(&1, :tag) == tag)) do
      nil ->
        :error

      %{name: name, fields: []} ->
        normalized = %{"ctor" => name, "args" => []}
        {name, normalized}

      %{name: name, fields: [field]} ->
        if composite_watch_to_phone_field?(field) do
          :error
        else
          decoded_arg = decode_watch_to_phone_scalar_field(schema, field, value)
          normalized = %{"ctor" => name, "args" => [decoded_arg]}
          {protocol_message_display(name, [decoded_arg]), normalized}
        end

      _ ->
        :error
    end
  end

  @spec composite_watch_to_phone_field?(Types.protocol_field()) :: boolean()
  defp composite_watch_to_phone_field?(%{wire_type: {:record, _, _}}), do: true
  defp composite_watch_to_phone_field?(%{wire_type: {:list, _}}), do: true
  defp composite_watch_to_phone_field?(%{wire_type: {:dict, _}}), do: true
  defp composite_watch_to_phone_field?(_field), do: false

  @spec decode_watch_to_phone_scalar_field(
          Types.protocol_schema(),
          Types.protocol_field(),
          integer()
        ) :: Types.protocol_wire_arg()
  defp decode_watch_to_phone_scalar_field(schema, %{wire_type: {:union, type}}, value)
       when is_map(schema) and is_binary(type) and is_integer(value) do
    union_ctors = Map.get(schema, :payload_unions, %{}) |> Map.get(type, [])

    case Enum.at(union_ctors, value - Ide.CompanionProtocolGenerator.wire_code_base()) do
      %{name: ctor, args: []} when is_binary(ctor) ->
        %{"ctor" => ctor, "args" => []}

      %{name: ctor} when is_binary(ctor) ->
        %{"ctor" => ctor, "args" => [0]}

      _ ->
        value
    end
  end

  defp decode_watch_to_phone_scalar_field(schema, field, value) do
    normalize_protocol_wire_value(schema, value, Map.get(field, :wire_type))
  end

  @spec protocol_schema_message(
          Types.protocol_schema(),
          :watch_to_phone | :phone_to_watch,
          String.t()
        ) :: Types.protocol_schema_message() | nil
  defp protocol_schema_message(schema, direction, ctor)
       when is_map(schema) and is_binary(ctor) do
    schema
    |> Map.get(direction, [])
    |> Enum.find(&(Map.get(&1, :name) == ctor))
  end

  @spec protocol_message_ctor(Types.protocol_message_wire_value()) :: String.t() | nil
  def protocol_message_ctor(%{"ctor" => ctor}) when is_binary(ctor), do: ctor
  def protocol_message_ctor(%{ctor: ctor}) when is_binary(ctor), do: ctor
  def protocol_message_ctor(%{"$ctor" => ctor}) when is_binary(ctor), do: ctor
  def protocol_message_ctor(_), do: nil

  @spec protocol_message_args(Types.protocol_message_wire_value(), non_neg_integer()) ::
          [Types.protocol_wire_arg()]
  defp protocol_message_args(%{"args" => args}, field_count) when is_list(args),
    do: flatten_protocol_args(args, field_count)

  defp protocol_message_args(%{args: args}, field_count) when is_list(args),
    do: flatten_protocol_args(args, field_count)

  defp protocol_message_args(%{"$args" => args}, field_count) when is_list(args),
    do: flatten_protocol_args(args, field_count)

  defp protocol_message_args(_message_value, _field_count), do: []

  @spec flatten_protocol_args([Types.protocol_wire_arg()], non_neg_integer()) ::
          [Types.protocol_wire_arg()]
  defp flatten_protocol_args(args, field_count)
       when is_list(args) and is_integer(field_count) and field_count > 0 do
    cond do
      length(args) == field_count ->
        args

      length(args) == 1 ->
        flatten_protocol_tuple_chain(hd(args), field_count)

      length(args) < field_count ->
        case List.last(args) do
          nil ->
            args

          tail ->
            prefix = Enum.drop(args, -1)
            flattened_tail = flatten_protocol_tuple_chain(tail, field_count - length(prefix))
            prefix ++ flattened_tail
        end

      true ->
        Enum.take(args, field_count)
    end
  end

  defp flatten_protocol_args(args, _field_count) when is_list(args), do: args

  @spec flatten_protocol_tuple_chain(Types.protocol_wire_arg(), non_neg_integer()) ::
          [Types.protocol_wire_arg()]
  defp flatten_protocol_tuple_chain(value, count) when is_integer(count) and count > 0 do
    do_flatten_protocol_tuple_chain(value, count, [])
  end

  defp flatten_protocol_tuple_chain(value, _count), do: [value]

  defp do_flatten_protocol_tuple_chain(value, 1, acc), do: Enum.reverse([value | acc])

  defp do_flatten_protocol_tuple_chain({left, right}, count, acc) when count > 1,
    do: do_flatten_protocol_tuple_chain(right, count - 1, [left | acc])

  defp do_flatten_protocol_tuple_chain(
         %{"type" => "tuple2", "children" => [left, right]},
         count,
         acc
       )
       when count > 1,
       do: do_flatten_protocol_tuple_chain(right, count - 1, [left | acc])

  defp do_flatten_protocol_tuple_chain(%{type: "tuple2", children: [left, right]}, count, acc)
       when count > 1,
       do: do_flatten_protocol_tuple_chain(right, count - 1, [left | acc])

  defp do_flatten_protocol_tuple_chain(value, _count, acc), do: Enum.reverse([value | acc])

  @spec message_constructor(String.t()) :: String.t() | nil
  defp message_constructor(message) when is_binary(message) do
    message
    |> String.trim()
    |> String.split(~r/\s+/, parts: 2)
    |> List.first()
  end

  @spec protocol_constructor_value?(Types.protocol_ctor_value()) :: boolean()
  defp protocol_constructor_value?(%{"ctor" => ctor}) when is_binary(ctor), do: true
  defp protocol_constructor_value?(%{ctor: ctor}) when is_binary(ctor), do: true
  defp protocol_constructor_value?(%{"$ctor" => ctor}) when is_binary(ctor), do: true
  defp protocol_constructor_value?(_value), do: false

  @spec protocol_message_display(String.t(), [Types.protocol_wire_arg()]) :: String.t()
  defp protocol_message_display(ctor, args) when is_binary(ctor) and is_list(args) do
    case args do
      [] -> ctor
      _ -> ctor <> " " <> Enum.map_join(args, " ", &protocol_arg_display/1)
    end
  end

  @spec protocol_arg_display(Types.protocol_wire_arg()) :: String.t()
  defp protocol_arg_display(%{"ctor" => ctor, "args" => args}) when is_binary(ctor) and is_list(args) do
    protocol_message_display(ctor, args)
  end

  defp protocol_arg_display(%{ctor: ctor, args: args}) when is_binary(ctor) and is_list(args) do
    protocol_message_display(ctor, args)
  end

  defp protocol_arg_display(value) when is_binary(value), do: inspect(value)

  defp protocol_arg_display(value) when is_integer(value) or is_float(value) or is_boolean(value),
    do: to_string(value)

  defp protocol_arg_display(value), do: inspect(value)

  @spec normalize_protocol_wire_value(
          Types.protocol_schema(),
          Types.protocol_wire_arg(),
          Types.protocol_wire_type()
        ) :: Types.protocol_wire_arg()
  defp normalize_protocol_wire_value(schema, %{"$ctor" => ctor, "$args" => args}, wire_type)
       when is_map(schema) and is_binary(ctor) do
    normalize_protocol_wire_value(
      schema,
      %{"ctor" => ctor, "args" => Enum.map(List.wrap(args), &normalize_elmc_wire_ctor/1)},
      wire_type
    )
  end

  defp normalize_protocol_wire_value(schema, value, {:enum, type})
       when is_map(schema) and is_binary(type) do
    value = normalize_elmc_wire_ctor(value)

    cond do
      protocol_constructor_value?(value) ->
        value

      true ->
        if is_integer(value) do
          enum_values = Map.get(schema, :enums, %{}) |> Map.get(type, [])

          case Enum.at(enum_values, value - Ide.CompanionProtocolGenerator.wire_code_base()) do
            ctor when is_binary(ctor) and ctor != "" ->
              %{"ctor" => ctor, "args" => []}

            _ ->
              value
          end
        else
          value
        end
    end
  end

  defp normalize_protocol_wire_value(_schema, value, _wire_type),
    do: normalize_elmc_wire_ctor(value)

  @spec normalize_elmc_wire_ctor(Types.protocol_wire_arg()) :: Types.protocol_wire_arg()
  def normalize_elmc_wire_ctor(%{"$ctor" => ctor, "$args" => args}) when is_binary(ctor) do
    %{
      "ctor" => ctor,
      "args" => Enum.map(List.wrap(args), &normalize_elmc_wire_ctor/1)
    }
  end

  def normalize_elmc_wire_ctor(%{"ctor" => ctor, "args" => args}) when is_binary(ctor) do
    %{
      "ctor" => ctor,
      "args" => Enum.map(List.wrap(args), &normalize_elmc_wire_ctor/1)
    }
  end

  def normalize_elmc_wire_ctor(%{ctor: ctor, args: args}) when is_binary(ctor) do
    %{
      "ctor" => ctor,
      "args" => Enum.map(List.wrap(args), &normalize_elmc_wire_ctor/1)
    }
  end

  def normalize_elmc_wire_ctor(value), do: value
end
