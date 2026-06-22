defmodule Ide.Debugger.CompanionBridge.Runtime do
  @moduledoc false

  alias Ide.Debugger.CompanionBridge
  alias Ide.Debugger.CompanionBridge.SimulatorStore
  alias Ide.Debugger.Geolocation
  alias Ide.Debugger.IntrospectAccess
  alias Ide.Debugger.Types

  @companion_bridge_targets [:companion, :phone]

  @type ctx :: %{
          required(:introspect) => (Types.runtime_state(), Types.surface_target() ->
                                      Types.elm_introspect()),
          required(:cmd_calls) => (Types.elm_introspect(), String.t() -> [Types.cmd_call()]),
          required(:bridge_requests_from_init) => (Types.runtime_state(),
                                                   Types.surface_target() ->
                                                     [Types.companion_bridge_request()]),
          required(:bridge_requests_from_update) => (Types.runtime_state(),
                                                     Types.surface_target(),
                                                     String.t() ->
                                                       [Types.companion_bridge_request()]),
          required(:append_event) => (Types.runtime_state(),
                                      String.t(),
                                      Types.debugger_timeline_payload() ->
                                        Types.runtime_state()),
          required(:apply_step) => (Types.runtime_state(),
                                    Types.surface_target(),
                                    String.t(),
                                    Types.subscription_payload()
                                    | nil,
                                    String.t(),
                                    String.t() ->
                                      Types.runtime_state()),
          required(:settings) => (Types.runtime_state() -> Types.simulator_settings())
        }

  @skipped_message_sources ~w(
    companion_bridge
    companion_bridge_command
    init_companion_bridge
    simulator_settings
    subscription_trigger
    protocol_rx
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

  def maybe_apply_command_responses(state, _target, _message, _model, _message_source, _ctx),
    do: state

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

  @spec maybe_apply_subscription_responses(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          ctx()
        ) ::
          Types.runtime_state()
  def maybe_apply_subscription_responses(state, target, source, ctx)
      when target in @companion_bridge_targets and is_map(state) and is_binary(source) and
             is_map(ctx) do
    Enum.reduce(CompanionBridge.subscription_contracts(), state, fn contract, acc ->
      trigger = Map.fetch!(contract, :source)

      if trigger == "weather" and source == "simulator_settings" do
        acc
      else
        apply_subscription_contract(acc, target, source, contract, ctx)
      end
    end)
  end

  def maybe_apply_subscription_responses(state, _target, _source, _ctx), do: state

  @spec maybe_apply_weather_settings_change(
          Types.runtime_state(),
          Types.simulator_settings(),
          Types.simulator_settings(),
          ctx()
        ) :: Types.runtime_state()
  def maybe_apply_weather_settings_change(state, previous_settings, new_settings, ctx)
      when is_map(state) and is_map(previous_settings) and is_map(new_settings) and is_map(ctx) do
    previous_weather = Map.get(previous_settings, "weather") || %{}
    new_weather = Map.get(new_settings, "weather") || %{}

    with true <- new_weather != %{} and new_weather != previous_weather,
         true <- companion_weather_delivery_ready?(state),
         %{} = contract <-
           Enum.find(CompanionBridge.subscription_contracts(), &(Map.get(&1, :source) == "weather")) do
      apply_subscription_contract(state, :companion, "simulator_settings", contract, ctx)
    else
      _ -> state
    end
  end

  def maybe_apply_weather_settings_change(state, _previous_settings, _new_settings, _ctx),
    do: state

  defp apply_subscription_contract(state, target, source, contract, ctx)
       when target in @companion_bridge_targets and is_map(state) and is_binary(source) and
              is_map(contract) and is_map(ctx) do
    trigger = Map.fetch!(contract, :source)
    callback = subscription_callback_from_state(state, target, contract, ctx)

    case callback do
      value when is_binary(value) and value != "" ->
        payload = bridge_payload(state, Map.fetch!(contract, :payload), %{op: "subscribe"}, ctx)

        state
        |> ctx.append_event.(
          "debugger.companion_bridge",
          Ide.Debugger.Types.CompanionBridgeEventPayload.from_subscription(
            source_root_for_target(target),
            trigger,
            callback,
            payload
          )
        )
        |> apply_subscription_response(
          target,
          callback,
          payload,
          source,
          trigger,
          contract,
          ctx
        )

      _ ->
        state
    end
  end

  defp companion_weather_delivery_ready?(state) when is_map(state) do
    case get_in(state, [:companion, :model, "runtime_model"]) ||
           get_in(state, [:phone, :model, "runtime_model"]) do
      %{"lastCondition" => %{"ctor" => "Just", "args" => [_]}} ->
        true

      %{"lastResponse" => response} when is_integer(response) and response != 0 ->
        true

      _ ->
        false
    end
  end

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
  @pending_bridge_steps_key :pending_companion_bridge_steps

  def apply_requests(requests, state, target, source, ctx)
      when target in @companion_bridge_targets and is_list(requests) and is_map(state) and
             is_binary(source) and is_map(ctx) do
    {state, deferred_steps} =
      Enum.reduce(requests, {state, []}, fn request, {acc, steps} ->
        {next_state, request_steps} = apply_request(acc, target, request, source, ctx)
        {next_state, steps ++ request_steps}
      end)

    enqueue_deferred_steps(state, deferred_steps)
  end

  def apply_requests(_requests, state, _target, _source, _ctx), do: state

  @spec subscription_callback_from_state(
          Types.runtime_state(),
          Types.surface_target(),
          Types.companion_subscription_contract() | Types.api_suffix_contract(),
          ctx()
        ) :: String.t() | nil
  def subscription_callback_from_state(state, target, contract, ctx)
      when is_map(state) and target in [:watch, :companion, :phone] and is_map(contract) and
             is_map(ctx) do
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
  def subscription_callback(ei, contract, ctx)
      when is_map(ei) and is_map(contract) and is_map(ctx) do
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

  @type deferred_bridge_step :: %{
          required(:target) => :watch | :companion | :phone,
          required(:message) => String.t(),
          required(:message_value) => Types.subscription_payload() | nil,
          required(:source) => String.t(),
          required(:trigger) => String.t()
        }

  @spec apply_request(
          Types.runtime_state(),
          :companion,
          Types.companion_bridge_request(),
          String.t(),
          ctx()
        ) :: {Types.runtime_state(), [deferred_bridge_step()]}
  defp apply_request(state, _target, %{api: "storage", op: op} = request, _source, ctx)
       when op in ["set", "remove", "clear"] do
    {next_state, _result} = storage_result(state, request, ctx)
    {next_state, []}
  end

  defp apply_request(state, target, %{api: "storage"} = request, source, ctx) do
    callback = bridge_callback(request, state, target, CompanionBridge.storage_contract(), ctx)

    case callback do
      value when is_binary(value) and value != "" ->
        {next_state, result} = storage_result(state, request, ctx)

        apply_callback(next_state, target, callback, result, source, "storage", request, ctx)

      _ ->
        {state, []}
    end
  end

  defp apply_request(state, _target, %{api: "preferences", op: "set"} = request, _source, ctx) do
    {next_state, _result} = preferences_result(state, request, ctx)
    {next_state, []}
  end

  defp apply_request(state, target, %{api: "preferences"} = request, source, ctx) do
    callback =
      bridge_callback(request, state, target, CompanionBridge.preferences_contract(), ctx)

    case callback do
      value when is_binary(value) and value != "" ->
        {next_state, result} = preferences_result(state, request, ctx)

        apply_callback(next_state, target, callback, result, source, "preferences", request, ctx)

      _ ->
        {state, []}
    end
  end

  defp apply_request(state, target, %{api: "geolocation"} = request, source, ctx) do
    callback =
      bridge_callback(request, state, target, CompanionBridge.geolocation_contract(), ctx)

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
        {state, []}
    end
  end

  defp apply_request(state, target, %{api: "webSocket"} = request, source, ctx) do
    callback = bridge_callback(request, state, target, %{}, ctx)

    case callback do
      value when is_binary(value) and value != "" ->
        apply_callback(state, target, callback, {:ok, %{}}, source, "webSocket", request, ctx)

      _ ->
        {state, []}
    end
  end

  defp apply_request(state, target, %{api: api} = request, source, ctx) when is_binary(api) do
    contract =
      Enum.find(CompanionBridge.subscription_contracts(), &(Map.fetch!(&1, :source) == api))

    callback =
      if contract, do: bridge_callback(request, state, target, contract, ctx), else: nil

    case {contract, callback} do
      {%{} = found_contract, value} when is_binary(value) and value != "" ->
        payload = bridge_payload(state, Map.fetch!(found_contract, :payload), request, ctx)

        apply_callback(state, target, callback, {:ok, payload}, source, api, request, ctx)

      _ ->
        {state, []}
    end
  end

  defp apply_request(state, _target, _request, _source, _ctx), do: {state, []}

  @spec apply_subscription_response(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          Types.companion_bridge_payload(),
          String.t(),
          String.t(),
          Types.companion_subscription_contract() | Types.api_suffix_contract(),
          ctx()
        ) :: Types.runtime_state()
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
    {step_target, step_trigger, message, message_value} =
      phone_to_watch_step(state, callback, payload, contract, trigger, ctx)

    steps =
      [
        companion_subscription_deferred_step(state, callback, payload, source, trigger, ctx),
        deferred_bridge_step(step_target, message, message_value, source, step_trigger)
      ]
      |> Enum.reject(&is_nil/1)

    apply_deferred_steps(state, steps, ctx)
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
          {:watch | :companion | :phone, String.t(), String.t(),
           Types.phone_to_watch_message_value()}
  defp phone_to_watch_step(state, callback, payload, %{source: source} = contract, _trigger, _ctx)
       when is_map(state) and callback in ["FromPhone" | @companion_phone_status_callbacks] and
              source in @phone_to_watch_contract_sources do
    normalized = normalize_companion_subscription_payload(payload, contract)
    message_value = phone_to_watch_message_value(contract, normalized)
    message = phone_to_watch_step_message(contract, normalized)

    {:watch, "phone_to_watch", message, message_value}
  end

  defp phone_to_watch_step(state, callback, payload, %{source: "weather"}, trigger, ctx)
       when is_map(state) and is_binary(callback) and is_map(ctx) do
    target = companion_app_step_target(state, ctx, callback)
    message_value = CompanionBridge.subscription_message_value("weather", callback, "Ok", payload)
    {target, trigger, callback, message_value}
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

  defp phone_to_watch_message_value(_contract, payload),
    do: %{"ctor" => "FromPhone", "args" => [payload]}

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
       when is_map(state) and is_binary(callback) and is_binary(source) and is_binary(api) and
              is_map(ctx) do
    plain? = Map.get(request, :plain_result) == true

    {result_ctor, payload} =
      if plain? do
        {"plain", connectivity, _wrapped} =
          CompanionBridge.plain_connectivity_parts(callback, result)

        {"plain", connectivity}
      else
        CompanionBridge.callback_result_parts(result)
      end

    state =
      ctx.append_event.(
        state,
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

    contract =
      CompanionBridge.contract_for_source(api) ||
        %{source: api, plain_result: plain?}

    {step_target, step_trigger, message, step_value} =
      phone_to_watch_step(state, callback, payload, contract, source, ctx)

    steps =
      [
        companion_subscription_deferred_step(state, callback, payload, source, api, ctx),
        deferred_bridge_step(step_target, message, step_value, source, step_trigger)
      ]
      |> Enum.reject(&is_nil/1)

    {state, steps}
  end

  @spec flush_deferred_steps(Types.runtime_state(), ctx()) :: Types.runtime_state()
  def flush_deferred_steps(state, ctx) when is_map(state) and is_map(ctx) do
    steps =
      state
      |> Map.get(@pending_bridge_steps_key, [])
      |> case do
        list when is_list(list) -> list
        _ -> []
      end

    state
    |> Map.delete(@pending_bridge_steps_key)
    |> apply_deferred_steps(steps, ctx)
  end

  def flush_deferred_steps(state, _ctx), do: state

  @spec enqueue_deferred_steps(Types.runtime_state(), [deferred_bridge_step()]) ::
          Types.runtime_state()
  defp enqueue_deferred_steps(state, []), do: state

  defp enqueue_deferred_steps(state, steps) when is_list(steps) do
    Map.update(state, @pending_bridge_steps_key, steps, &(&1 ++ steps))
  end

  @spec apply_deferred_steps(Types.runtime_state(), [deferred_bridge_step()], ctx()) ::
          Types.runtime_state()
  defp apply_deferred_steps(state, steps, ctx) when is_map(state) and is_list(steps) and is_map(ctx) do
    Enum.reduce(steps, state, fn step, acc ->
      ctx.apply_step.(
        acc,
        step.target,
        step.message,
        step.message_value,
        step.source,
        step.trigger
      )
    end)
  end

  @spec deferred_bridge_step(
          :watch | :companion | :phone,
          String.t(),
          Types.subscription_payload() | nil,
          String.t(),
          String.t()
        ) :: deferred_bridge_step()
  defp deferred_bridge_step(target, message, message_value, source, trigger)
       when target in [:watch, :companion, :phone] and is_binary(message) and is_binary(source) and
              is_binary(trigger) do
    %{
      target: target,
      message: message,
      message_value: message_value,
      source: source,
      trigger: trigger
    }
  end

  @spec companion_subscription_deferred_step(
          Types.runtime_state(),
          String.t(),
          Types.companion_bridge_payload(),
          String.t(),
          String.t(),
          ctx()
        ) :: deferred_bridge_step() | nil
  defp companion_subscription_deferred_step(state, callback, payload, source, trigger, ctx)
       when callback in @companion_phone_status_callbacks do
    target = companion_app_step_target(state, ctx, callback)

    deferred_bridge_step(
      target,
      callback,
      subscription_ok_message_value(callback, payload),
      source,
      trigger
    )
  end

  defp companion_subscription_deferred_step(_state, _callback, _payload, _source, _trigger, _ctx),
    do: nil

  @spec bridge_payload(
          Types.runtime_state(),
          atom(),
          Types.CompanionBridgeRequest.wire_map(),
          ctx()
        ) ::
          Types.companion_bridge_payload()
  defp bridge_payload(state, kind, request, ctx) when is_map(state) and is_map(ctx) do
    CompanionBridge.payload(ctx.settings.(state), kind, request)
  end

  @spec storage_result(Types.runtime_state(), Types.wire_map(), ctx()) ::
          {Types.runtime_state(), {:ok, Types.wire_map()} | {:error, String.t()}}
  defp storage_result(state, request, ctx)
       when is_map(state) and is_map(request) and is_map(ctx) do
    settings = ctx.settings.(state)
    {next_settings, result} = SimulatorStore.storage_result(settings, request)
    {Map.put(state, :simulator_settings, next_settings), result}
  end

  @spec preferences_result(Types.runtime_state(), Types.wire_map(), ctx()) ::
          {Types.runtime_state(), {:ok, {String.t(), Types.wire_input()}} | {:error, String.t()}}
  defp preferences_result(state, request, ctx)
       when is_map(state) and is_map(request) and is_map(ctx) do
    settings = ctx.settings.(state)
    {next_settings, result} = SimulatorStore.preferences_result(settings, request)
    {Map.put(state, :simulator_settings, next_settings), result}
  end

  @spec companion_app_step_target(Types.runtime_state(), ctx(), String.t()) :: :companion | :phone
  defp companion_app_step_target(state, ctx, callback)
       when is_map(state) and is_map(ctx) and is_binary(callback) do
    if callback_known_on_surface?(state, ctx, :phone, callback) do
      :phone
    else
      :companion
    end
  end

  @spec callback_known_on_surface?(
          Types.runtime_state(),
          ctx(),
          Types.surface_target(),
          String.t()
        ) ::
          boolean()
  defp callback_known_on_surface?(state, ctx, target, callback)
       when is_map(state) and is_map(ctx) and is_binary(callback) do
    state
    |> ctx.introspect.(target)
    |> introspect_known_messages()
    |> Enum.any?(fn known -> known == callback or String.starts_with?(known, callback <> " ") end)
  end

  @spec introspect_known_messages(Types.elm_introspect() | nil) :: [String.t()]
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
