defmodule Ide.Debugger.CompanionBridge.Runtime do
  @moduledoc false

  alias Ide.Debugger.CompanionBridge
  alias Ide.Debugger.CompanionBridge.SimulatorStore
  alias Ide.Debugger.Geolocation
  alias Ide.Debugger.Types

  @type ctx :: %{
          required(:introspect) => (map(), Types.surface_target() -> Types.elm_introspect() | map()),
          required(:cmd_calls) => (map(), String.t() -> [Types.cmd_call()]),
          required(:bridge_requests_from_init) => (map(), :companion -> [Types.companion_bridge_request()]),
          required(:bridge_requests_from_update) =>
            (map(), :companion, String.t() -> [Types.companion_bridge_request()]),
          required(:append_event) => (map(), String.t(), map() -> map()),
          required(:apply_step) =>
            (map(), Types.surface_target(), String.t(), Types.subscription_payload() | map() | nil, String.t(),
             String.t() -> map()),
          required(:deliver_weather_to_watch) => (map() -> map()),
          required(:settings) => (map() -> map())
        }

  @skipped_message_sources ~w(
    companion_bridge
    companion_bridge_command
    init_companion_bridge
    simulator_settings
    subscription_trigger
  )

  @spec maybe_apply_command_responses(
          map(),
          Types.surface_target(),
          String.t(),
          map(),
          String.t(),
          ctx()
        ) :: map()
  def maybe_apply_command_responses(
        state,
        :companion = target,
        message,
        model,
        message_source,
        ctx
      )
      when is_map(state) and is_binary(message) and is_map(model) and is_map(ctx) do
    if message_source in ["companion_bridge_command", "init_companion_bridge"] do
      state
    else
      ctx.bridge_requests_from_update.(state, target, message)
      |> apply_requests(state, target, "companion_bridge_command", ctx)
    end
  end

  def maybe_apply_command_responses(state, _target, _message, _model, _message_source, _ctx), do: state

  @spec maybe_apply_responses(map(), Types.surface_target(), String.t(), ctx()) :: map()
  def maybe_apply_responses(state, :companion = target, message_source, ctx)
      when is_map(state) and is_map(ctx) do
    if message_source in (@skipped_message_sources ++ CompanionBridge.sources()) do
      state
    else
      maybe_apply_subscription_responses(state, target, "companion_bridge", ctx)
    end
  end

  def maybe_apply_responses(state, _target, _message_source, _ctx), do: state

  @spec maybe_apply_subscription_responses(map(), Types.surface_target(), String.t(), ctx()) :: map()
  def maybe_apply_subscription_responses(state, :companion = target, source, ctx)
      when is_map(state) and is_binary(source) and is_map(ctx) do
    Enum.reduce(CompanionBridge.subscription_contracts(), state, fn contract, acc ->
      callback = subscription_callback_from_state(acc, target, contract, ctx)

      case callback do
        value when is_binary(value) and value != "" ->
          payload = bridge_payload(acc, Map.fetch!(contract, :payload), %{op: "subscribe"}, ctx)
          trigger = Map.fetch!(contract, :source)

          acc
          |> ctx.append_event.(
            "debugger.companion_bridge",
            Ide.Debugger.Types.CompanionBridgeEventPayload.from_subscription(
              source_root_for_target(target),
              trigger,
              callback,
              payload
            )
          )
          |> apply_subscription_response(target, callback, payload, source, trigger, contract, ctx)

        _ ->
          acc
      end
    end)
  end

  def maybe_apply_subscription_responses(state, _target, _source, _ctx), do: state

  @spec apply_init_commands(map(), :companion, ctx()) :: map()
  def apply_init_commands(state, :companion = target, ctx) when is_map(state) and is_map(ctx) do
    ctx.bridge_requests_from_init.(state, target)
    |> apply_requests(state, target, "init_companion_bridge", ctx)
  end

  def apply_init_commands(state, _target, _ctx), do: state

  @spec apply_requests([Types.companion_bridge_request()], map(), :companion, String.t(), ctx()) :: map()
  def apply_requests(requests, state, :companion = target, source, ctx)
      when is_list(requests) and is_map(state) and is_binary(source) and is_map(ctx) do
    Enum.reduce(requests, state, &apply_request(&2, target, &1, source, ctx))
  end

  def apply_requests(_requests, state, _target, _source, _ctx), do: state

  @spec subscription_callback_from_state(map(), Types.surface_target(), map(), ctx()) :: String.t() | nil
  def subscription_callback_from_state(state, target, contract, ctx)
      when is_map(state) and target in [:watch, :companion, :phone] and is_map(contract) and is_map(ctx) do
    state
    |> ctx.introspect.(target)
    |> subscription_callback(contract, ctx)
  end

  def subscription_callback_from_state(_state, _target, _contract, _ctx), do: nil

  @spec subscription_callback(Types.elm_introspect() | map(), map(), ctx()) :: String.t() | nil
  def subscription_callback(ei, contract, ctx) when is_map(ei) and is_map(contract) and is_map(ctx) do
    target_suffixes = Map.get(contract, :target_suffixes, []) |> List.wrap()

    ei
    |> ctx.cmd_calls.("subscription_calls")
    |> Enum.find_value(fn row ->
      if Ide.Debugger.CmdCall.subscription_call_matches?(row, target_suffixes) do
        callback = Map.get(row, "callback_constructor")

        if is_binary(callback) and callback != "", do: callback, else: nil
      end
    end)
  end

  def subscription_callback(_ei, _contract, _ctx), do: nil

  @spec apply_request(map(), :companion, Types.companion_bridge_request(), String.t(), ctx()) :: map()
  defp apply_request(state, _target, %{api: "storage", op: op} = request, _source, ctx)
       when op in ["set", "remove", "clear"] do
    {next_state, _result} = storage_result(state, request, ctx)
    next_state
  end

  defp apply_request(state, target, %{api: "storage"} = request, source, ctx) do
    callback = bridge_callback(request, state, target, CompanionBridge.storage_contract(), ctx)

    case callback do
      value when is_binary(value) and value != "" ->
        {next_state, result} = storage_result(state, request, ctx)

        apply_callback(next_state, target, callback, result, source, "storage", request, ctx)

      _ ->
        state
    end
  end

  defp apply_request(state, _target, %{api: "preferences", op: "set"} = request, _source, ctx) do
    {next_state, _result} = preferences_result(state, request, ctx)
    next_state
  end

  defp apply_request(state, target, %{api: "preferences"} = request, source, ctx) do
    callback = bridge_callback(request, state, target, CompanionBridge.preferences_contract(), ctx)

    case callback do
      value when is_binary(value) and value != "" ->
        {next_state, result} = preferences_result(state, request, ctx)

        apply_callback(next_state, target, callback, result, source, "preferences", request, ctx)

      _ ->
        state
    end
  end

  defp apply_request(state, target, %{api: "geolocation"} = request, source, ctx) do
    callback = bridge_callback(request, state, target, CompanionBridge.geolocation_contract(), ctx)

    case callback do
      value when is_binary(value) and value != "" ->
        apply_callback(
          state,
          target,
          callback,
          {:ok, Geolocation.location_from_state(state)},
          source,
          "geolocation",
          request,
          ctx
        )

      _ ->
        state
    end
  end

  defp apply_request(state, target, %{api: "weather"} = request, _source, ctx) do
    contract =
      Enum.find(CompanionBridge.subscription_contracts(), &(Map.fetch!(&1, :source) == "weather"))

    callback =
      if contract, do: bridge_callback(request, state, target, contract, ctx), else: nil

    payload = bridge_payload(state, :weather, request, ctx)

    state
    |> ctx.append_event.(
      "debugger.companion_bridge",
      Ide.Debugger.Types.CompanionBridgeEventPayload.from_response(
        source_root_for_target(target),
        "weather",
        Map.get(request, :op),
        callback,
        payload,
        "Ok"
      )
    )
    |> ctx.deliver_weather_to_watch.()
  end

  defp apply_request(state, target, %{api: api} = request, source, ctx)
       when is_binary(api) and api != "weather" do
    contract =
      Enum.find(CompanionBridge.subscription_contracts(), &(Map.fetch!(&1, :source) == api))

    callback =
      if contract, do: bridge_callback(request, state, target, contract, ctx), else: nil

    case {contract, callback} do
      {%{} = found_contract, value} when is_binary(value) and value != "" ->
        payload = bridge_payload(state, Map.fetch!(found_contract, :payload), request, ctx)

        apply_callback(state, target, callback, {:ok, payload}, source, api, request, ctx)

      _ ->
        state
    end
  end

  defp apply_request(state, _target, _request, _source, _ctx), do: state

  @spec apply_subscription_response(
          map(),
          Types.surface_target(),
          String.t(),
          Types.companion_bridge_payload(),
          String.t(),
          String.t(),
          map(),
          ctx()
        ) :: map()
  def apply_subscription_response(
        state,
        :companion = _target,
        callback,
        payload,
        source,
        "weather" = _trigger,
        _contract,
        ctx
      )
      when is_map(state) and is_binary(callback) and is_binary(source) and is_map(ctx) do
    state
    |> ctx.append_event.(
      "debugger.companion_bridge",
      Ide.Debugger.Types.CompanionBridgeEventPayload.from_subscription(
        source_root_for_target(:companion),
        "weather",
        callback,
        payload
      )
    )
    |> ctx.deliver_weather_to_watch.()
  end

  def apply_subscription_response(
        state,
        target,
        callback,
        payload,
        source,
        trigger,
        contract,
        ctx
      )
      when is_map(state) and target in [:watch, :companion, :phone] and is_binary(callback) and
             is_binary(source) and is_binary(trigger) and is_map(contract) and is_map(ctx) do
    if Map.get(contract, :plain_result) == true do
      connectivity =
        cond do
          payload == true -> %{"ctor" => "Online", "args" => []}
          payload == false -> %{"ctor" => "Offline", "args" => []}
          is_map(payload) -> payload
          true -> %{"ctor" => "Offline", "args" => []}
        end

      ctx.apply_step.(
        state,
        target,
        callback,
        %{"ctor" => callback, "args" => [connectivity]},
        source,
        trigger
      )
    else
      ctx.apply_step.(
        state,
        target,
        callback,
        subscription_ok_message_value(callback, payload),
        source,
        trigger
      )
    end
  end

  @spec subscription_ok_message_value(String.t(), Types.companion_bridge_payload()) :: map()
  defp subscription_ok_message_value(callback, payload) when is_binary(callback) do
    CompanionBridge.subscription_result_message_value(callback, "Ok", payload)
  end

  defp bridge_callback(%{callback: callback}, _state, _target, _contract, _ctx)
       when is_binary(callback) and callback != "",
       do: callback

  defp bridge_callback(request, state, target, contract, ctx) when is_map(request) do
    subscription_callback_from_state(state, target, contract, ctx)
  end

  defp apply_callback(state, target, callback, result, source, api, request, ctx)
       when is_map(state) and is_binary(callback) and is_binary(source) and is_binary(api) and is_map(ctx) do
    plain? = Map.get(request, :plain_result) == true

    {result_ctor, payload, message_value} =
      if plain? do
        CompanionBridge.plain_connectivity_parts(callback, result)
      else
        {result_ctor, payload} = CompanionBridge.callback_result_parts(result)

        message_value =
          CompanionBridge.subscription_message_value(api, callback, result_ctor, payload)

        {result_ctor, payload, message_value}
      end

    state
    |> ctx.append_event.(
      "debugger.companion_bridge",
      Ide.Debugger.Types.CompanionBridgeEventPayload.from_response(
        source_root_for_target(target),
        api,
        Map.get(request, :op),
        callback,
        payload,
        result_ctor
      )
    )
    |> then(fn next_state ->
      ctx.apply_step.(next_state, target, callback, message_value, source, api)
    end)
  end

  @spec bridge_payload(map(), atom(), map(), ctx()) :: Types.companion_bridge_payload()
  defp bridge_payload(state, kind, request, ctx) when is_map(state) and is_map(ctx) do
    CompanionBridge.payload(ctx.settings.(state), kind, request)
  end

  @spec storage_result(map(), map(), ctx()) :: {map(), {:ok, map()} | {:error, String.t()}}
  defp storage_result(state, request, ctx) when is_map(state) and is_map(request) and is_map(ctx) do
    settings = ctx.settings.(state)
    {next_settings, result} = SimulatorStore.storage_result(settings, request)
    {Map.put(state, :simulator_settings, next_settings), result}
  end

  @spec preferences_result(map(), map(), ctx()) ::
          {map(), {:ok, {String.t(), Types.wire_input()}} | {:error, String.t()}}
  defp preferences_result(state, request, ctx) when is_map(state) and is_map(request) and is_map(ctx) do
    settings = ctx.settings.(state)
    {next_settings, result} = SimulatorStore.preferences_result(settings, request)
    {Map.put(state, :simulator_settings, next_settings), result}
  end

  @spec source_root_for_target(:companion) :: String.t()
  defp source_root_for_target(:companion), do: "phone"
end
