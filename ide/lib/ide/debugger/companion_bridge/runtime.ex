defmodule Ide.Debugger.CompanionBridge.Runtime do
  @moduledoc false

  alias Ide.Debugger.CompanionBridge
  alias Ide.Debugger.CompanionBridge.SimulatorStore
  alias Ide.Debugger.Geolocation
  alias Ide.Debugger.IntrospectAccess
  alias Ide.Debugger.Types

  @companion_bridge_targets [:companion, :phone]

  @type ctx :: %{
          required(:introspect) =>
            (Types.runtime_state(), Types.surface_target() -> Types.elm_introspect()),
          required(:cmd_calls) => (Types.elm_introspect(), String.t() -> [Types.cmd_call()]),
          required(:bridge_requests_from_init) =>
            (Types.runtime_state(), Types.surface_target() -> [Types.companion_bridge_request()]),
          required(:bridge_requests_from_update) =>
            (Types.runtime_state(), Types.surface_target(), String.t() ->
               [Types.companion_bridge_request()]),
          required(:append_event) =>
            (Types.runtime_state(), String.t(), Types.debugger_timeline_payload() ->
               Types.runtime_state()),
          required(:apply_step) =>
            (Types.runtime_state(), Types.surface_target(), String.t(),
             Types.subscription_payload() | nil, String.t(), String.t() -> Types.runtime_state()),
          required(:deliver_weather_to_watch) => (Types.runtime_state() -> Types.runtime_state()),
          required(:settings) => (Types.runtime_state() -> Types.simulator_settings())
        }

  @skipped_message_sources ~w(
    companion_bridge
    companion_bridge_command
    init_companion_bridge
    simulator_settings
    subscription_trigger
  )

  @spec maybe_apply_command_responses(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          Types.app_model(),
          String.t(),
          ctx()
        ) :: Types.runtime_state()
  def maybe_apply_command_responses(
        state,
        target,
        message,
        model,
        message_source,
        ctx
      )
      when target in @companion_bridge_targets and is_map(state) and is_binary(message) and
             is_map(model) and is_map(ctx) do
    if message_source in ["companion_bridge_command", "init_companion_bridge"] do
      state
    else
      ctx.bridge_requests_from_update.(state, target, message)
      |> apply_requests(state, target, "companion_bridge_command", ctx)
    end
  end

  def maybe_apply_command_responses(state, _target, _message, _model, _message_source, _ctx), do: state

  @spec maybe_apply_responses(Types.runtime_state(), Types.surface_target(), String.t(), ctx()) ::
          Types.runtime_state()
  def maybe_apply_responses(state, target, message_source, ctx)
      when target in @companion_bridge_targets and is_map(state) and is_map(ctx) do
    if message_source in (@skipped_message_sources ++ CompanionBridge.sources()) do
      state
    else
      maybe_apply_subscription_responses(state, target, "companion_bridge", ctx)
    end
  end

  def maybe_apply_responses(state, _target, _message_source, _ctx), do: state

  @spec maybe_apply_subscription_responses(Types.runtime_state(), Types.surface_target(), String.t(), ctx()) ::
          Types.runtime_state()
  def maybe_apply_subscription_responses(state, target, source, ctx)
      when target in @companion_bridge_targets and is_map(state) and is_binary(source) and is_map(ctx) do
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

  @spec apply_init_commands(Types.runtime_state(), Types.surface_target(), ctx()) ::
          Types.runtime_state()
  def apply_init_commands(state, target, ctx)
      when target in @companion_bridge_targets and is_map(state) and is_map(ctx) do
    ctx.bridge_requests_from_init.(state, target)
    |> apply_requests(state, target, "init_companion_bridge", ctx)
  end

  def apply_init_commands(state, _target, _ctx), do: state

  @spec apply_requests(
          [Types.companion_bridge_request()],
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          ctx()
        ) :: Types.runtime_state()
  def apply_requests(requests, state, target, source, ctx)
      when target in @companion_bridge_targets and is_list(requests) and is_map(state) and
             is_binary(source) and is_map(ctx) do
    Enum.reduce(requests, state, &apply_request(&2, target, &1, source, ctx))
  end

  def apply_requests(_requests, state, _target, _source, _ctx), do: state

  @spec subscription_callback_from_state(
          Types.runtime_state(),
          Types.surface_target(),
          Types.companion_subscription_contract() | Types.api_suffix_contract(),
          ctx()
        ) :: String.t() | nil
  def subscription_callback_from_state(state, target, contract, ctx)
      when is_map(state) and target in [:watch, :companion, :phone] and is_map(contract) and is_map(ctx) do
    state
    |> ctx.introspect.(target)
    |> subscription_callback(contract, ctx)
  end

  def subscription_callback_from_state(_state, _target, _contract, _ctx), do: nil

  @spec subscription_callback(
          Types.elm_introspect(),
          Types.companion_subscription_contract() | Types.api_suffix_contract(),
          ctx()
        ) :: String.t() | nil
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

  @spec apply_request(
          Types.runtime_state(),
          :companion,
          Types.companion_bridge_request(),
          String.t(),
          ctx()
        ) :: Types.runtime_state()
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

  defp apply_request(state, target, %{api: "webSocket"} = request, source, ctx) do
    callback = bridge_callback(request, state, target, %{}, ctx)

    case callback do
      value when is_binary(value) and value != "" ->
        apply_callback(state, target, callback, {:ok, %{}}, source, "webSocket", request, ctx)

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
        _target,
        callback,
        payload,
        source,
        trigger,
        contract,
        ctx
      )
      when is_map(state) and is_binary(callback) and is_binary(source) and is_binary(trigger) and
             is_map(contract) and is_map(ctx) do
    state = maybe_apply_companion_subscription_step(state, callback, payload, source, trigger, ctx)

    {step_target, step_trigger, message, message_value} =
      phone_to_watch_step(state, callback, payload, contract, trigger, ctx)

    ctx.apply_step.(state, step_target, message, message_value, source, step_trigger)
  end

  @phone_to_watch_contract_sources ~w(battery locale network notifications)
  @companion_phone_status_callbacks ~w(GotBattery GotLocale GotConnectivity GotNotifications)

  @spec phone_to_watch_step(
          Types.runtime_state(),
          String.t(),
          Types.phone_to_watch_payload(),
          Types.companion_subscription_contract() | Types.api_suffix_contract(),
          String.t(),
          ctx()
        ) ::
          {:watch | :companion | :phone, String.t(), String.t(), Types.phone_to_watch_message_value()}
  defp phone_to_watch_step(state, callback, payload, %{source: source} = contract, _trigger, _ctx)
       when is_map(state) and callback in ["FromPhone" | @companion_phone_status_callbacks] and
              source in @phone_to_watch_contract_sources do
    normalized = normalize_companion_subscription_payload(payload, contract)
    message_value = phone_to_watch_message_value(contract, normalized)
    message = phone_to_watch_step_message(contract, normalized)

    {:watch, "phone_to_watch", message, message_value}
  end

  defp phone_to_watch_step(state, callback, payload, _contract, trigger, ctx)
       when is_map(state) and is_binary(callback) and is_map(ctx) do
    target = companion_app_step_target(state, ctx, callback)
    {target, trigger, callback, subscription_ok_message_value(callback, payload)}
  end

  defp normalize_companion_subscription_payload(%{"ctor" => "Ok", "args" => [inner]}, contract),
    do: normalize_companion_subscription_payload(inner, contract)

  defp normalize_companion_subscription_payload({:ok, inner}, contract),
    do: normalize_companion_subscription_payload(inner, contract)

  defp normalize_companion_subscription_payload(%{"locale" => locale}, %{source: "locale"})
       when is_binary(locale),
       do: locale

  defp normalize_companion_subscription_payload(payload, _contract), do: payload

  @spec phone_to_watch_message_value(
          Types.companion_subscription_source(),
          Types.phone_to_watch_payload()
        ) :: Types.phone_to_watch_message_value()
  defp phone_to_watch_message_value(%{source: "battery"}, payload) when is_map(payload) do
    %{
      "ctor" => "FromPhone",
      "args" => [
        %{
          "ctor" => "ProvideBattery",
          "args" => [Map.get(payload, "percent"), Map.get(payload, "charging")]
        }
      ]
    }
  end

  defp phone_to_watch_message_value(%{source: "locale"}, payload) when is_binary(payload) do
    %{
      "ctor" => "FromPhone",
      "args" => [%{"ctor" => "ProvideLocale", "args" => [payload]}]
    }
  end

  defp phone_to_watch_message_value(%{source: "locale"}, %{"locale" => locale})
       when is_binary(locale) do
    phone_to_watch_message_value(%{source: "locale"}, locale)
  end

  defp phone_to_watch_message_value(%{source: "network", plain_result: true}, online)
       when is_boolean(online) do
    phone_to_watch_connectivity_value(online)
  end

  defp phone_to_watch_message_value(%{source: "network", plain_result: true}, payload)
       when is_map(payload) do
    phone_to_watch_connectivity_value(connectivity_online?(payload))
  end

  defp phone_to_watch_message_value(%{source: "notifications"}, payload) when is_map(payload) do
    notifications_enabled =
      Map.get(payload, "notificationsEnabled", Map.get(payload, "notifications_enabled"))

    quiet_hours = Map.get(payload, "quietHours", Map.get(payload, "quiet_hours"))

    %{
      "ctor" => "FromPhone",
      "args" => [
        %{
          "ctor" => "ProvideNotifications",
          "args" => [notifications_enabled, quiet_hours]
        }
      ]
    }
  end

  defp phone_to_watch_message_value(_contract, payload) when is_map(payload), do: payload
  defp phone_to_watch_message_value(_contract, payload), do: %{"ctor" => "FromPhone", "args" => [payload]}

  defp phone_to_watch_connectivity_value(online) when is_boolean(online) do
    %{
      "ctor" => "FromPhone",
      "args" => [%{"ctor" => "ProvideConnectivity", "args" => [online]}]
    }
  end

  defp connectivity_online?(%{"ctor" => "Online"}), do: true
  defp connectivity_online?(%{"ctor" => "Offline"}), do: false
  defp connectivity_online?(_), do: false

  @spec phone_to_watch_step_message(
          Types.companion_subscription_source(),
          Types.phone_to_watch_payload()
        ) :: String.t()
  defp phone_to_watch_step_message(%{source: "battery"}, payload) when is_map(payload) do
    "FromPhone (ProvideBattery #{Map.get(payload, "percent")} #{Map.get(payload, "charging")})"
  end

  defp phone_to_watch_step_message(%{source: "locale"}, locale) when is_binary(locale) do
    "FromPhone (ProvideLocale #{locale})"
  end

  defp phone_to_watch_step_message(%{source: "locale"}, %{"locale" => locale})
       when is_binary(locale) do
    phone_to_watch_step_message(%{source: "locale"}, locale)
  end

  defp phone_to_watch_step_message(%{source: "network", plain_result: true}, online)
       when is_boolean(online) do
    "FromPhone (ProvideConnectivity #{online})"
  end

  defp phone_to_watch_step_message(%{source: "network", plain_result: true}, payload)
       when is_map(payload) do
    "FromPhone (ProvideConnectivity #{connectivity_online?(payload)})"
  end

  defp phone_to_watch_step_message(%{source: "notifications"}, payload) when is_map(payload) do
    enabled = Map.get(payload, "notificationsEnabled", Map.get(payload, "notifications_enabled"))
    quiet = Map.get(payload, "quietHours", Map.get(payload, "quiet_hours"))
    "FromPhone (ProvideNotifications #{enabled} #{quiet})"
  end

  defp phone_to_watch_step_message(_contract, _payload), do: "FromPhone"

  @spec subscription_ok_message_value(String.t(), Types.companion_bridge_payload()) ::
          Types.protocol_ctor_value()
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

    {result_ctor, payload} =
      if plain? do
        {"plain", connectivity, _wrapped} =
          CompanionBridge.plain_connectivity_parts(callback, result)

        {"plain", connectivity}
      else
        CompanionBridge.callback_result_parts(result)
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
      next_state =
        maybe_apply_companion_subscription_step(next_state, callback, payload, source, api, ctx)

      contract =
        CompanionBridge.contract_for_source(api) ||
          %{source: api, plain_result: plain?}

      {step_target, step_trigger, message, step_value} =
        phone_to_watch_step(next_state, callback, payload, contract, source, ctx)

      ctx.apply_step.(next_state, step_target, message, step_value, source, step_trigger)
    end)
  end

  defp maybe_apply_companion_subscription_step(state, callback, payload, source, trigger, ctx)
       when callback in @companion_phone_status_callbacks do
    target = companion_app_step_target(state, ctx, callback)

    ctx.apply_step.(
      state,
      target,
      callback,
      subscription_ok_message_value(callback, payload),
      source,
      trigger
    )
  end

  defp maybe_apply_companion_subscription_step(state, _callback, _payload, _source, _trigger, _ctx),
    do: state

  @spec bridge_payload(Types.runtime_state(), atom(), Types.CompanionBridgeRequest.wire_map(), ctx()) ::
          Types.companion_bridge_payload()
  defp bridge_payload(state, kind, request, ctx) when is_map(state) and is_map(ctx) do
    CompanionBridge.payload(ctx.settings.(state), kind, request)
  end

  @spec storage_result(Types.runtime_state(), Types.wire_map(), ctx()) ::
          {Types.runtime_state(), {:ok, Types.wire_map()} | {:error, String.t()}}
  defp storage_result(state, request, ctx) when is_map(state) and is_map(request) and is_map(ctx) do
    settings = ctx.settings.(state)
    {next_settings, result} = SimulatorStore.storage_result(settings, request)
    {Map.put(state, :simulator_settings, next_settings), result}
  end

  @spec preferences_result(Types.runtime_state(), Types.wire_map(), ctx()) ::
          {Types.runtime_state(), {:ok, {String.t(), Types.wire_input()}} | {:error, String.t()}}
  defp preferences_result(state, request, ctx) when is_map(state) and is_map(request) and is_map(ctx) do
    settings = ctx.settings.(state)
    {next_settings, result} = SimulatorStore.preferences_result(settings, request)
    {Map.put(state, :simulator_settings, next_settings), result}
  end

  @spec companion_app_step_target(Types.runtime_state(), ctx(), String.t()) :: :companion | :phone
  defp companion_app_step_target(state, ctx, callback) when is_map(state) and is_map(ctx) and is_binary(callback) do
    if callback_known_on_surface?(state, ctx, :phone, callback) do
      :phone
    else
      :companion
    end
  end

  @spec callback_known_on_surface?(Types.runtime_state(), ctx(), Types.surface_target(), String.t()) ::
          boolean()
  defp callback_known_on_surface?(state, ctx, target, callback)
       when is_map(state) and is_map(ctx) and is_binary(callback) do
    state
    |> ctx.introspect.(target)
    |> introspect_known_messages()
    |> Enum.any?(fn known -> known == callback or String.starts_with?(known, callback <> " ") end)
  end

  @spec introspect_known_messages(Types.elm_introspect() | map() | nil) :: [String.t()]
  defp introspect_known_messages(ei) when is_map(ei) do
    msg_constructors = IntrospectAccess.list(ei, "msg_constructors")
    update_branches = IntrospectAccess.list(ei, "update_case_branches")

    if msg_constructors != [], do: msg_constructors, else: update_branches
  end

  defp introspect_known_messages(_), do: []

  @spec source_root_for_target(:companion | :phone) :: String.t()
  defp source_root_for_target(:companion), do: "phone"
  defp source_root_for_target(:phone), do: "phone"
end
