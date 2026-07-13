defmodule Ide.Debugger.ProtocolRx do
  @moduledoc false

  alias Ide.Debugger.AppMessageQueue
  alias Ide.Debugger.PendingProtocolDelivery
  alias Ide.Debugger.StepDepth
  alias Ide.Debugger.ProtocolEvents
  alias Ide.Debugger.ProtocolEvents.CmdCall.Core, as: ProtocolCmdCallCore
  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.SurfaceTargets
  alias Ide.Debugger.Types

  @type ctx :: %{
          required(:append_event) => (Types.runtime_state(),
                                      String.t(),
                                      Types.debugger_timeline_payload() ->
                                        Types.runtime_state()),
          required(:append_debugger_event) => (Types.runtime_state(),
                                               String.t(),
                                               Types.surface_target(),
                                               String.t(),
                                               String.t(),
                                               Types.debugger_timeline_payload()
                                               | nil ->
                                                 Types.runtime_state()),
          required(:append_runtime_exec_event_for_target) => (Types.runtime_state(),
                                                              Types.surface_target(),
                                                              Types.debugger_timeline_payload() ->
                                                                Types.runtime_state()),
          required(:source_root_for_target) => (Types.surface_target() -> String.t()),
          required(:introspect_for) => (Types.runtime_state(), Types.surface_target() ->
                                          Types.elm_introspect()),
          required(:introspect_cmd_calls) => (Types.elm_introspect(), String.t() ->
                                                [Types.cmd_call()]),
          required(:apply_step_once) => (Types.runtime_state(),
                                         Types.surface_target(),
                                         String.t(),
                                         Types.subscription_payload()
                                         | nil,
                                         String.t(),
                                         String.t() ->
                                           Types.runtime_state()),
          required(:refresh_runtime_fingerprints) => (Types.execution_model(),
                                                      Types.app_model(),
                                                      Types.app_model() ->
                                                        Types.execution_model()),
          required(:protocol_events_ctx) => (-> ProtocolEvents.ctx()),
          required(:runtime_ready_for_delivery?) => (Types.runtime_state(),
                                                     Types.surface_target() ->
                                                       boolean())
        }

  @init_complete_key "debugger_init_complete"
  @inline_deliveries_key :pending_inline_protocol_deliveries

  @spec runtime_ready_for_delivery?(Types.runtime_state(), Types.surface_target()) :: boolean()
  def runtime_ready_for_delivery?(state, target)
      when is_map(state) and target in [:watch, :companion, :phone] do
    surface = Map.get(state, target, %{})
    model = Map.get(surface, :model) || Map.get(surface, "model") || %{}

    is_map(RuntimeArtifacts.introspect(surface)) and
      Map.get(model, @init_complete_key) == true and
      Map.get(model, "runtime_execution_mode") == "runtime_executed"
  end

  def runtime_ready_for_delivery?(_state, _target), do: false

  @spec mark_init_complete(Types.runtime_state(), Types.surface_target()) :: Types.runtime_state()
  def mark_init_complete(state, target)
      when is_map(state) and target in [:watch, :companion, :phone] do
    state
    |> put_init_complete_on(target)
    |> then(fn st ->
      if target == :companion and Map.has_key?(st, :phone) do
        put_init_complete_on(st, :phone)
      else
        st
      end
    end)
  end

  def mark_init_complete(state, _target), do: state

  defp put_init_complete_on(state, target) do
    surface = Map.get(state, target, %{})
    model = Map.get(surface, :model) || Map.get(surface, "model") || %{}

    Map.put(state, target, Map.put(surface, :model, Map.put(model, @init_complete_key, true)))
  end

  @spec apply_side_effects(
          Types.runtime_state(),
          [Types.protocol_timeline_event()],
          boolean(),
          ctx()
        ) :: Types.runtime_state()
  def apply_side_effects(state, _protocol_events, true, _ctx), do: state

  def apply_side_effects(state, protocol_events, false, rx_ctx)
      when is_list(protocol_events) and is_map(rx_ctx) do
    state
    |> append_transport_events(protocol_events, rx_ctx)
    |> apply_state_effects(protocol_events, rx_ctx)
  end

  def apply_side_effects(state, _protocol_events, _suppress?, _ctx), do: state

  @spec append_events(Types.runtime_state(), [Types.protocol_timeline_event()], ctx()) ::
          Types.runtime_state()
  def append_events(state, protocol_events, rx_ctx) do
    append_transport_events(state, protocol_events, rx_ctx)
  end

  @spec append_transport_events(Types.runtime_state(), [Types.protocol_timeline_event()], ctx()) ::
          Types.runtime_state()
  def append_transport_events(state, protocol_events, rx_ctx)
      when is_list(protocol_events) and is_map(rx_ctx) do
    Enum.reduce(protocol_events, state, fn event, acc ->
      if event.type == "debugger.protocol_tx" and is_map(event.payload) do
        rx_ctx.append_event.(acc, event.type, event.payload)
      else
        acc
      end
    end)
  end

  @spec apply_state_effects(Types.runtime_state(), [Types.protocol_timeline_event()], ctx()) ::
          Types.runtime_state()
  def apply_state_effects(state, protocol_events, rx_ctx)
      when is_list(protocol_events) and is_map(rx_ctx) do
    Enum.reduce(protocol_events, state, fn event, acc ->
      if event.type == "debugger.protocol_rx" and is_map(event.payload) do
        payload = event.payload

        recipient =
          payload
          |> Map.get(:to)
          |> case do
            nil -> Map.get(payload, "to")
            value -> value
          end
          |> protocol_surface_key()

        cond do
          defer_init_cmd_delivery?(payload) and recipient in [:watch, :companion, :phone] ->
            if rx_ctx.runtime_ready_for_delivery?.(acc, recipient) do
              PendingProtocolDelivery.enqueue(acc, recipient, payload)
            else
              AppMessageQueue.enqueue(acc, recipient, payload)
            end

          inline_step_delivery?(payload) ->
            enqueue_inline_protocol_delivery(acc, payload)

          true ->
            handle_protocol_rx_event(acc, payload, rx_ctx)
        end
      else
        acc
      end
    end)
  end

  @spec flush_inline_protocol_deliveries(Types.runtime_state(), ctx()) :: Types.runtime_state()
  def flush_inline_protocol_deliveries(state, rx_ctx) when is_map(state) and is_map(rx_ctx) do
    if StepDepth.nested?() do
      state
    else
      state
      |> Map.get(@inline_deliveries_key, [])
      |> case do
        deliveries when is_list(deliveries) and deliveries != [] ->
          state
          |> Map.delete(@inline_deliveries_key)
          |> deliver_inline_protocol_payloads(Enum.reverse(deliveries), rx_ctx)

        _ ->
          Map.delete(state, @inline_deliveries_key)
      end
    end
  end

  def flush_inline_protocol_deliveries(state, _rx_ctx) when is_map(state), do: state

  @spec inline_protocol_deliveries(Types.runtime_state()) :: [Types.protocol_tx_rx_payload()]
  def inline_protocol_deliveries(state) when is_map(state) do
    case Map.get(state, @inline_deliveries_key) do
      deliveries when is_list(deliveries) -> deliveries
      _ -> []
    end
  end

  @spec enqueue_inline_protocol_delivery(
          Types.runtime_state(),
          Types.protocol_tx_rx_payload()
        ) :: Types.runtime_state()
  def enqueue_inline_protocol_delivery(state, payload) when is_map(state) and is_map(payload) do
    Map.update(state, @inline_deliveries_key, [payload], &[payload | &1])
  end

  @spec inline_step_delivery?(Types.protocol_tx_rx_payload()) :: boolean()
  defp inline_step_delivery?(payload) when is_map(payload) do
    trigger = Map.get(payload, :trigger) || Map.get(payload, "trigger")
    source = Map.get(payload, :message_source) || Map.get(payload, "message_source")
    from = Map.get(payload, :from) || Map.get(payload, "from")
    to = Map.get(payload, :to) || Map.get(payload, "to")

    runtime_cmd? = trigger == "runtime_cmd" or source == "runtime_cmd"

    phone_to_watch? =
      from in ["companion", "phone"] and to == "watch"

    watch_to_phone? =
      from == "watch" and to in ["companion", "phone"]

    phone_to_watch? or (runtime_cmd? and watch_to_phone?)
  end

  @spec deliver_inline_protocol_payloads(
          Types.runtime_state(),
          [Types.protocol_tx_rx_payload()],
          ctx()
        ) :: Types.runtime_state()
  defp deliver_inline_protocol_payloads(state, deliveries, rx_ctx)
       when is_map(state) and is_list(deliveries) and is_map(rx_ctx) do
    deliveries
    |> Enum.uniq_by(&inline_delivery_key/1)
    |> Enum.reduce(state, fn payload, acc ->
      handle_protocol_rx_event(acc, payload, rx_ctx)
    end)
  end

  @spec inline_delivery_key(Types.protocol_tx_rx_payload()) ::
          {String.t() | nil, String.t() | nil, Types.subscription_payload() | nil}
  defp inline_delivery_key(payload) when is_map(payload) do
    {
      Map.get(payload, :to) || Map.get(payload, "to"),
      Map.get(payload, :message) || Map.get(payload, "message"),
      Map.get(payload, :message_value) || Map.get(payload, "message_value")
    }
  end

  defp handle_protocol_rx_event(state, payload, rx_ctx) when is_map(payload) and is_map(rx_ctx) do
    recipient = protocol_surface_key(Map.get(payload, :to) || Map.get(payload, "to"))

    if recipient in [:watch, :companion, :phone] do
      cond do
        not rx_ctx.runtime_ready_for_delivery?.(state, recipient) ->
          AppMessageQueue.enqueue(state, recipient, payload)

        defer_init_cmd_delivery?(payload) ->
          PendingProtocolDelivery.enqueue(state, recipient, payload)

        PendingProtocolDelivery.async?() ->
          PendingProtocolDelivery.enqueue(state, recipient, payload)

        true ->
          deliver_protocol_rx_to_surface(state, payload, rx_ctx)
      end
    else
      state
    end
  end

  @spec defer_init_cmd_delivery?(Types.protocol_tx_rx_payload()) :: boolean()
  defp defer_init_cmd_delivery?(payload) when is_map(payload) do
    trigger = Map.get(payload, :trigger) || Map.get(payload, "trigger")
    from = Map.get(payload, :from) || Map.get(payload, "from")
    to = Map.get(payload, :to) || Map.get(payload, "to")

    from == "watch" and to in ["companion", "phone"] and
      trigger in ["init_cmd", "init_companion_bridge", "runtime_cmd"]
  end

  defp defer_init_cmd_delivery?(_payload), do: false

  @spec deliver_payload(
          Types.runtime_state(),
          Types.protocol_tx_rx_payload(),
          ctx()
        ) :: Types.runtime_state()
  def deliver_payload(state, payload, rx_ctx)
      when is_map(state) and is_map(payload) and is_map(rx_ctx) do
    deliver_protocol_rx_to_surface(state, payload, rx_ctx)
  end

  defp deliver_protocol_rx_to_surface(state, payload, rx_ctx)
       when is_map(payload) and is_map(rx_ctx) do
    {next_state, recipient, meta} = apply_protocol_rx_effect(state, payload, rx_ctx)

    if recipient in [:watch, :companion, :phone] do
      next_state =
        next_state
        |> rx_ctx.append_event.("debugger.protocol_rx", protocol_rx_event_payload(payload))

      case protocol_rx_subscription_message(next_state, recipient, meta, rx_ctx) do
        {message, message_value} when is_binary(message) and message != "" ->
          apply_protocol_rx_subscription(
            next_state,
            recipient,
            meta,
            message,
            message_value,
            rx_ctx
          )

        _ ->
          append_protocol_rx_timeline_events(next_state, recipient, meta, rx_ctx)
      end
    else
      next_state
    end
  end

  # When a subscription maps the inbound AppMessage to an Elm update, StepApply
  # records the user-facing timeline row; skip a separate protocol_rx row.
  defp append_protocol_rx_timeline_events(state, recipient, meta, rx_ctx)
       when is_map(state) and recipient in [:watch, :companion, :phone] and is_map(meta) and
              is_map(rx_ctx) do
    inbound_display_message =
      Map.get(meta, :inbound_display_message) || Map.get(meta, :message) || ""

    root =
      state
      |> get_in([recipient, :view_tree, "type"])
      |> case do
        value when is_binary(value) and value != "" -> value
        _ -> "simulated-root"
      end

    state
    |> rx_ctx.append_debugger_event.(
      "protocol_rx",
      recipient,
      inbound_display_message,
      "protocol_rx",
      Map.get(meta, :message_value)
    )
    |> then(fn st ->
      rx_ctx.append_runtime_exec_event_for_target.(st, recipient, %{
        trigger: "protocol_rx",
        message: Map.get(meta, :message),
        message_source: Map.get(meta, :message_source),
        protocol_from: Map.get(meta, :from),
        protocol_to: rx_ctx.source_root_for_target.(recipient),
        protocol_inbound_count: Map.get(meta, :inbound_count)
      })
    end)
    |> rx_ctx.append_event.(
      "debugger.update_in",
      Ide.Debugger.Types.MessageInEventPayload.from_message(
        rx_ctx.source_root_for_target.(recipient),
        Map.get(meta, :message),
        Map.get(meta, :message_source)
      )
    )
    |> rx_ctx.append_event.(
      "debugger.view_render",
      Ide.Debugger.Types.ViewRenderEventPayload.from_render(
        rx_ctx.source_root_for_target.(recipient),
        root
      )
    )
  end

  defp apply_protocol_rx_subscription(state, recipient, meta, message, message_value, rx_ctx)
       when is_map(state) and recipient in [:watch, :companion, :phone] and is_binary(message) and
              message != "" and is_map(meta) and is_map(rx_ctx) do
    source_override =
      if Map.get(meta, :trigger) == "configuration", do: "configuration", else: "protocol_rx"

    message_value =
      if is_map(message_value) do
        ProtocolEvents.normalize_subscription_message_value(
          state,
          recipient,
          message_value,
          rx_ctx.protocol_events_ctx.()
        )
      else
        message_value
      end

    state
    |> rx_ctx.apply_step_once.(recipient, message, message_value, source_override, "protocol_rx")
    |> restore_protocol_rx_metadata(recipient, meta)
  end

  defp apply_protocol_rx_effect(state, payload, rx_ctx) when is_map(payload) and is_map(rx_ctx) do
    recipient = protocol_surface_key(Map.get(payload, :to) || Map.get(payload, "to"))
    sender = Map.get(payload, :from) || Map.get(payload, "from")
    message = Map.get(payload, :message) || Map.get(payload, "message")
    message_value = Map.get(payload, :message_value) || Map.get(payload, "message_value")
    message_source = "protocol_rx"
    inbound_display_message = ProtocolEvents.inbound_display_message(message, message_value)

    if recipient in [:watch, :companion, :phone] and is_binary(message) do
      row = %{
        "from" => if(is_binary(sender), do: sender, else: "unknown"),
        "to" => surface_label(recipient),
        "message" => message,
        "message_value" => message_value,
        "trigger" => Map.get(payload, :trigger) || Map.get(payload, "trigger"),
        "message_source" =>
          Map.get(payload, :message_source) || Map.get(payload, "message_source")
      }

      next_state =
        state
        |> update_recipient_protocol_messages(recipient, row)
        |> put_in([recipient, :model, "protocol_last_inbound_message"], inbound_display_message)
        |> put_in(
          [recipient, :model, "protocol_last_inbound_from"],
          if(is_binary(sender), do: sender, else: "unknown")
        )
        |> update_in([recipient, :model, "protocol_inbound_count"], fn
          count when is_integer(count) and count >= 0 -> count + 1
          _ -> 1
        end)
        |> update_recipient_runtime_model_from_protocol(
          recipient,
          Map.put(row, "message", inbound_display_message)
        )
        |> update_recipient_protocol_view_tree(recipient, row)
        |> refresh_runtime_surface_fingerprints(recipient, rx_ctx)

      {
        next_state,
        recipient,
        %{
          message: message,
          inbound_display_message: inbound_display_message,
          message_value: message_value,
          message_source: message_source,
          from: if(is_binary(sender), do: sender, else: "unknown"),
          trigger: Map.get(payload, :trigger) || Map.get(payload, "trigger"),
          inbound_count: get_in(next_state, [recipient, :model, "protocol_inbound_count"]) || 0
        }
      }
    else
      {state, nil, %{}}
    end
  end

  @spec drain_message_queue(Types.runtime_state(), Types.surface_target(), ctx()) ::
          Types.runtime_state()
  def drain_message_queue(state, target, rx_ctx)
      when is_map(state) and target in [:watch, :companion, :phone] and is_map(rx_ctx) do
    {state, entries} = AppMessageQueue.drain_entries(state, target)

    Enum.reduce(entries, state, fn payload, acc ->
      cond do
        not rx_ctx.runtime_ready_for_delivery?.(acc, target) ->
          AppMessageQueue.enqueue(acc, target, payload)

        defer_init_cmd_delivery?(payload) ->
          PendingProtocolDelivery.enqueue(acc, target, payload)

        PendingProtocolDelivery.async?() ->
          PendingProtocolDelivery.enqueue(acc, target, payload)

        true ->
          deliver_protocol_rx_to_surface(acc, payload, rx_ctx)
      end
    end)
  end

  def drain_message_queue(state, _target, _ctx), do: state

  defp protocol_rx_event_payload(payload) when is_map(payload) do
    %{
      from: Map.get(payload, :from) || Map.get(payload, "from"),
      to: Map.get(payload, :to) || Map.get(payload, "to"),
      message: Map.get(payload, :message) || Map.get(payload, "message"),
      message_value: Map.get(payload, :message_value) || Map.get(payload, "message_value"),
      trigger: Map.get(payload, :trigger) || Map.get(payload, "trigger"),
      message_source: Map.get(payload, :message_source) || Map.get(payload, "message_source")
    }
  end

  defp restore_protocol_rx_metadata(state, recipient, meta)
       when is_map(state) and recipient in [:watch, :companion, :phone] and is_map(meta) do
    inbound_display_message =
      Map.get(meta, :inbound_display_message) || Map.get(meta, :message)

    state =
      state
      |> put_in([recipient, :model, "protocol_last_inbound_message"], inbound_display_message)
      |> put_in([recipient, :model, "protocol_last_inbound_from"], Map.get(meta, :from))
      |> put_in([recipient, :model, "protocol_inbound_count"], Map.get(meta, :inbound_count))

    if recipient in [:companion, :phone] do
      update_in(state, [recipient, :model, "runtime_model"], fn runtime_model ->
        runtime_model = if is_map(runtime_model), do: runtime_model, else: %{}

        runtime_model
        |> Map.put("protocol_last_inbound_message", inbound_display_message)
        |> Map.put("protocol_last_inbound_from", Map.get(meta, :from))
        |> Map.put("protocol_inbound_count", Map.get(meta, :inbound_count))
      end)
    else
      state
    end
  end

  defp protocol_rx_subscription_message(state, recipient, meta, rx_ctx)
       when is_map(state) and is_map(rx_ctx) and recipient in [:watch, :companion, :phone] and
              is_map(meta) do
    from = Map.get(meta, :from)
    message = Map.get(meta, :message)
    message_value = Map.get(meta, :message_value)

    cond do
      not is_binary(message) or message == "" ->
        nil

      recipient == :watch and from in ["companion", "phone"] ->
        callback =
          protocol_rx_subscription_callback(state, recipient, "on_phone_to_watch", rx_ctx) ||
            "FromPhone"

        protocol_callback_message(callback, message, message_value, false)

      recipient in [:companion, :phone] and from == "watch" ->
        callback =
          protocol_rx_subscription_callback(state, recipient, "on_watch_to_phone", rx_ctx) ||
            "FromWatch"

        protocol_callback_message(callback, message, message_value, true)

      true ->
        nil
    end
  end

  defp protocol_rx_subscription_message(_state, _recipient, _meta, _ctx), do: nil

  defp protocol_rx_subscription_callback(state, recipient, event_kind, rx_ctx)
       when is_map(state) and is_map(rx_ctx) and recipient in [:watch, :companion, :phone] and
              is_binary(event_kind) do
    state
    |> rx_ctx.introspect_for.(recipient)
    |> rx_ctx.introspect_cmd_calls.("subscription_calls")
    |> Enum.find_value(fn row ->
      if Map.get(row, "event_kind") == event_kind do
        callback = Map.get(row, "callback_constructor")
        if is_binary(callback) and callback != "", do: callback, else: nil
      end
    end)
  end

  defp protocol_rx_subscription_callback(_state, _recipient, _event_kind, _ctx), do: nil

  @spec protocol_callback_message(
          String.t() | nil,
          String.t(),
          Types.subscription_payload(),
          boolean()
        ) ::
          {String.t(), Types.protocol_message_wire_value()} | String.t() | nil
  defp protocol_callback_message(
         callback,
         _message,
         %{"ctor" => ctor, "args" => _} = message_value,
         false
       )
       when is_binary(callback) and callback != "" and callback == ctor do
    {callback, message_value}
  end

  defp protocol_callback_message(callback, message, message_value, wrap_result?)
       when is_binary(callback) and callback != "" and is_binary(message) and message != "" do
    already_wrapped? = wrap_result? and String.starts_with?(message, "#{callback} (Ok ")

    message =
      if already_wrapped? do
        message
      else
        ProtocolEvents.parenthesize_elm_arg(message)
      end

    {display, value} =
      cond do
        already_wrapped? and is_map(message_value) ->
          {
            message,
            ensure_protocol_callback_wire_value(callback, message_value)
          }

        wrap_result? ->
          {
            "#{callback} (Ok #{message})",
            if(is_map(message_value),
              do:
                wrap_protocol_callback_value(
                  callback,
                  %{"ctor" => "Ok", "args" => [message_value]}
                ),
              else: nil
            )
          }

        true ->
          inner_display = ProtocolEvents.inbound_display_message(message, message_value)

          display =
            if inner_display != message and String.contains?(inner_display, " ") do
              "#{callback} (#{inner_display})"
            else
              "#{callback} #{inner_display}"
            end

          {display, wrap_protocol_callback_value(callback, message_value)}
      end

    if is_map(value) do
      {display, value}
    else
      display
    end
  end

  defp protocol_callback_message(_callback, _message, _message_value, _wrap_result?), do: nil

  @doc false
  @spec inbound_app_message(String.t(), String.t(), Types.subscription_payload()) ::
          {String.t(), Types.protocol_message_wire_value()} | nil
  def inbound_app_message(callback, inner_message, message_value)
      when is_binary(callback) and is_binary(inner_message) do
    case protocol_callback_message(callback, inner_message, message_value, false) do
      {display, value} when is_binary(display) and is_map(value) -> {display, value}
      _ -> nil
    end
  end

  @doc false
  @spec inbound_watch_message(String.t(), String.t(), Types.subscription_payload() | nil) ::
          {String.t(), Types.protocol_message_wire_value()} | nil
  def inbound_watch_message(callback, inner_message, message_value)
      when is_binary(callback) and is_binary(inner_message) do
    case protocol_callback_message(callback, inner_message, message_value, true) do
      {display, value} when is_binary(display) and is_map(value) -> {display, value}
      _ -> nil
    end
  end

  @doc false
  @spec watch_to_phone_step_message(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          Types.subscription_payload() | nil,
          ctx()
        ) :: {String.t(), Types.subscription_payload() | nil}
  def watch_to_phone_step_message(state, recipient, message, message_value, rx_ctx)
      when is_map(state) and recipient in [:companion, :phone] and is_binary(message) and
             is_map(rx_ctx) do
    callback =
      protocol_rx_subscription_callback(state, recipient, "on_watch_to_phone", rx_ctx) ||
        "FromWatch"

    inbound_watch_message(callback, message, message_value) || {message, message_value}
  end

  @spec wrap_protocol_callback_value(String.t(), Types.subscription_payload()) ::
          Types.protocol_ctor_value() | nil
  defp wrap_protocol_callback_value(callback, %{"ctor" => ctor, "args" => _} = value)
       when is_binary(callback) and callback != "" and callback == ctor do
    value
  end

  defp wrap_protocol_callback_value(callback, %{ctor: ctor, args: _} = value)
       when is_binary(callback) and callback != "" and callback == ctor do
    value
  end

  defp wrap_protocol_callback_value(callback, value)
       when is_binary(callback) and callback != "" do
    %{"ctor" => callback, "args" => [protocol_callback_arg(value)]}
  end

  defp wrap_protocol_callback_value(_callback, _value), do: nil

  @spec ensure_protocol_callback_wire_value(String.t(), Types.subscription_payload()) ::
          Types.protocol_ctor_value()
  defp ensure_protocol_callback_wire_value(callback, %{"ctor" => ctor, "args" => _} = value)
       when is_binary(callback) and ctor == callback do
    value
  end

  defp ensure_protocol_callback_wire_value(callback, %{ctor: ctor, args: _} = value)
       when is_binary(callback) and ctor == callback do
    value
  end

  defp ensure_protocol_callback_wire_value(callback, value) when is_binary(callback) do
    normalized = ProtocolCmdCallCore.normalize_elmc_wire_ctor(value)

    %{
      "ctor" => callback,
      "args" => [%{"ctor" => "Ok", "args" => [normalized]}]
    }
  end

  @spec protocol_callback_arg(Types.subscription_payload()) :: Types.protocol_wire_arg()
  defp protocol_callback_arg(%{"ctor" => _, "args" => _} = value), do: value
  defp protocol_callback_arg(%{ctor: _, args: _} = value), do: value
  defp protocol_callback_arg(value) when is_integer(value), do: value
  defp protocol_callback_arg(value) when is_binary(value), do: value
  defp protocol_callback_arg(value) when is_boolean(value), do: value
  defp protocol_callback_arg(value) when is_list(value), do: value
  defp protocol_callback_arg(_value), do: nil

  @spec update_recipient_protocol_messages(
          Types.runtime_state(),
          Types.surface_target(),
          Types.protocol_tx_rx_payload()
        ) :: Types.runtime_state()
  defp update_recipient_protocol_messages(state, recipient, row)
       when recipient in [:watch, :companion, :phone] do
    update_in(state, [recipient, :protocol_messages], fn
      xs when is_list(xs) -> [row | xs] |> Enum.take(25)
      _ -> [row]
    end)
  end

  @spec update_recipient_runtime_model_from_protocol(
          Types.runtime_state(),
          Types.surface_target(),
          Types.protocol_tx_rx_payload()
        ) :: Types.runtime_state()
  defp update_recipient_runtime_model_from_protocol(state, recipient, row)
       when recipient in [:watch, :companion, :phone] and is_map(row) do
    inbound_count = get_in(state, [recipient, :model, "protocol_inbound_count"]) || 0

    state
    |> put_in([recipient, :model, "protocol_last_inbound_message"], row["message"])
    |> put_in([recipient, :model, "protocol_last_inbound_from"], row["from"])
    |> put_in([recipient, :model, "protocol_inbound_count"], inbound_count)
    |> put_in(
      [recipient, :model, "protocol_message_count"],
      length(get_in(state, [recipient, :protocol_messages]) || [])
    )
    |> put_in([recipient, :model, "protocol_last_trigger"], row["trigger"])
    |> maybe_update_protocol_runtime_model(recipient, row, inbound_count)
    |> put_in([recipient, :model, "runtime_last_message"], row["message"])
    |> put_in([recipient, :model, "runtime_message_source"], "protocol_rx")
  end

  defp maybe_update_protocol_runtime_model(state, :watch, _row, _inbound_count), do: state

  defp maybe_update_protocol_runtime_model(state, recipient, row, inbound_count)
       when recipient in [:companion, :phone] do
    update_in(state, [recipient, :model, "runtime_model"], fn runtime_model ->
      runtime_model = if is_map(runtime_model), do: runtime_model, else: %{}

      runtime_model
      |> Map.put("protocol_last_inbound_message", row["message"])
      |> Map.put("protocol_last_inbound_from", row["from"])
      |> Map.put("protocol_inbound_count", inbound_count)
      |> Map.put(
        "protocol_message_count",
        length(get_in(state, [recipient, :protocol_messages]) || [])
      )
    end)
  end

  @spec update_recipient_protocol_view_tree(
          Types.runtime_state(),
          Types.surface_target(),
          Types.protocol_tx_rx_payload()
        ) :: Types.runtime_state()
  defp update_recipient_protocol_view_tree(state, recipient, row)
       when recipient in [:watch, :companion, :phone] and is_map(row) do
    put_in(state, [recipient, :model, "protocol_last_view_message"], row["message"])
  end

  defp refresh_runtime_surface_fingerprints(state, recipient, rx_ctx)
       when recipient in [:watch, :companion, :phone] and is_map(rx_ctx) do
    model = get_in(state, [recipient, :model]) || %{}
    runtime_model = Map.get(model, "runtime_model")
    runtime_model = if is_map(runtime_model), do: runtime_model, else: %{}
    view_tree = get_in(state, [recipient, :view_tree]) || %{}

    put_in(
      state,
      [recipient, :model],
      rx_ctx.refresh_runtime_fingerprints.(model, runtime_model, view_tree)
    )
  end

  @spec protocol_surface_key(Types.surface_label_input()) :: :watch | :companion | :phone
  defp protocol_surface_key("watch"), do: :watch
  defp protocol_surface_key(label), do: SurfaceTargets.normalize(label)

  @spec surface_label(Types.surface_target()) :: String.t()
  defp surface_label(:watch), do: "watch"
  defp surface_label(:companion), do: "companion"
end
