defmodule Ide.Debugger.RuntimeActiveSubscriptions do
  @moduledoc false

  alias Ide.Debugger.CompanionSubscriptionTrigger
  alias Ide.Debugger.IntrospectAccess
  alias Ide.Debugger.RuntimeModelMessages
  alias Ide.Debugger.SubscriptionTriggerWire
  alias Ide.Debugger.Surface
  alias Ide.Debugger.TimelineMessage
  alias Ide.Debugger.TriggerCandidates
  alias Ide.Debugger.Types

  @type active_command :: Types.active_subscription()
  @type subscription_row_like :: Types.trigger_candidate() | Types.replay_row()
  @type subscription_row_ref :: subscription_row_like() | Types.subscription_row_input()

  @spec present?(Types.runtime_state(), Types.surface_target()) :: boolean()
  def present?(state, target) when is_map(state) and target in [:watch, :companion, :phone] do
    state
    |> Surface.from_state(target)
    |> Surface.app_model()
    |> Map.has_key?("active_subscriptions")
  end

  def present?(_state, _target), do: false

  @spec for_surface(Types.runtime_state(), Types.surface_target()) :: [active_command()]
  def for_surface(state, target) when is_map(state) and target in [:watch, :companion, :phone] do
    state
    |> Surface.from_state(target)
    |> Surface.app_model()
    |> Map.get("active_subscriptions", [])
    |> List.wrap()
    |> Enum.filter(&is_map/1)
  end

  def for_surface(_state, _target), do: []

  @spec row_active?(
          subscription_row_ref(),
          [active_command()]
        ) :: boolean()
  def row_active?(row, active) when is_map(row) and is_list(active) do
    row_trigger = row_trigger_id(row)
    row_message = row_message(row)

    Enum.any?(active, fn command ->
      command_trigger = command_trigger_id(command)
      command_message = command_message(command)

      triggers_equivalent?(row_trigger, command_trigger) and
        messages_compatible?(row_message, command_message)
    end)
  end

  def row_active?(_row, _active), do: false

  @spec match_for_row(
          Types.runtime_state(),
          Types.surface_target(),
          subscription_row_ref()
        ) :: active_command() | nil
  def match_for_row(state, target, row) when is_map(state) and is_map(row) do
    row_trigger = row_trigger_id(row)
    row_message = row_message(row)

    Enum.find(for_surface(state, target), fn command ->
      command_trigger = command_trigger_id(command)
      command_message = command_message(command)

      triggers_equivalent?(row_trigger, command_trigger) and
        messages_compatible?(row_message, command_message)
    end)
  end

  def match_for_row(_state, _target, _row), do: nil

  @spec for_target_patterns([String.t()], [active_command()]) :: [active_command()]
  def for_target_patterns(patterns, active) when is_list(patterns) and is_list(active) do
    normalized_patterns = Enum.map(patterns, &normalize_target_pattern/1)

    Enum.filter(active, fn command ->
      target = command_target(command)
      is_binary(target) and target_matches_patterns?(target, normalized_patterns)
    end)
  end

  @spec any_target_patterns?([String.t()], [active_command()]) :: boolean()
  def any_target_patterns?(patterns, active) when is_list(patterns) and is_list(active) do
    for_target_patterns(patterns, active) != []
  end

  @spec message_for_trigger(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          String.t() | nil
        ) ::
          {:ok, String.t(), Types.subscription_payload() | nil} | :error
  def message_for_trigger(state, target, trigger, requested_message)
      when is_map(state) and target in [:watch, :companion, :phone] and is_binary(trigger) do
    if is_binary(requested_message) and requested_message != "" do
      :error
    else
      case command_for_trigger(state, target, trigger) do
        %{} = command ->
          message = command_message(command)

          if message != "" do
            {:ok, message, Map.get(command, "message_value") || Map.get(command, :message_value)}
          else
            :error
          end

        _ ->
          :error
      end
    end
  end

  def message_for_trigger(_state, _target, _trigger, _requested_message), do: :error

  @spec command_for_trigger(
          Types.runtime_state(),
          Types.surface_target(),
          String.t()
        ) :: active_command() | nil
  def command_for_trigger(state, target, trigger)
      when is_map(state) and target in [:watch, :companion, :phone] and is_binary(trigger) do
    normalized = TriggerCandidates.normalize_trigger_id(trigger)
    active = for_surface(state, target)

    Enum.find(active, fn command ->
      triggers_equivalent?(normalized, command_trigger_id(command)) and
        command_message(command) != ""
    end) ||
      Enum.find(active, fn command ->
        triggers_equivalent?(normalized, command_trigger_id(command))
      end)
  end

  def command_for_trigger(_state, _target, _trigger), do: nil

  @spec command_message(active_command()) :: String.t()
  def command_message(command) when is_map(command) do
    command
    |> Map.get("message", Map.get(command, :message))
    |> to_string()
    |> String.trim()
  end

  def command_message(_command), do: ""

  @spec format_step_message(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          String.t()
        ) :: {:ok, String.t(), Types.subscription_payload() | nil} | :error
  def format_step_message(state, target, trigger, message)
      when is_map(state) and target in [:watch, :companion, :phone] and is_binary(message) do
    row = %{trigger: trigger, message: message}

    case match_for_row(state, target, row) do
      %{} = command ->
        ctor = command_message(command)
        value = Map.get(command, "message_value") || Map.get(command, :message_value)

        if ctor != "" do
          {:ok, TimelineMessage.format(ctor, value), value}
        else
          :error
        end

      _ ->
        :error
    end
  end

  def format_step_message(_state, _target, _trigger, _message), do: :error

  @spec trigger_candidates(
          Types.runtime_state(),
          Types.surface_target(),
          Types.elm_introspect(),
          String.t(),
          (Types.trigger_candidate() -> boolean())
        ) :: [Types.trigger_candidate()]
  def trigger_candidates(state, target, ei, target_name, model_active_fn)
      when is_map(state) and target in [:watch, :companion, :phone] and is_binary(target_name) and
             is_function(model_active_fn, 1) do
    ei = if is_map(ei), do: ei, else: %{}

    state
    |> for_surface(target)
    |> Enum.map(&trigger_row_from_command(&1, ei, target_name, model_active_fn))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(fn row -> {row.trigger, row.message} end)
  end

  def trigger_candidates(_state, _target, _ei, _target_name, _model_active_fn), do: []

  @spec message_value_for(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          String.t()
        ) :: Types.subscription_payload() | nil
  def message_value_for(state, target, trigger, message)
      when is_map(state) and target in [:watch, :companion, :phone] and is_binary(trigger) do
    row = %{trigger: trigger, message: message || ""}

    case match_for_row(state, target, row) do
      %{} = command -> Map.get(command, "message_value") || Map.get(command, :message_value)
      _ -> nil
    end
  end

  def message_value_for(_state, _target, _trigger, _message), do: nil

  @spec auto_fire_intervals(Types.runtime_state(), Types.surface_target()) :: [pos_integer()]
  def auto_fire_intervals(state, target) when is_map(state) and target in [:watch, :companion, :phone] do
    state
    |> for_surface(target)
    |> Enum.map(fn command ->
      Map.get(command, "interval_ms") || Map.get(command, :interval_ms)
    end)
    |> Enum.filter(&is_integer/1)
    |> Enum.map(&TriggerCandidates.clamp_auto_fire_interval_ms/1)
  end

  def auto_fire_intervals(_state, _target), do: []

  @type tick_candidate :: %{required(:message) => String.t(), required(:trigger) => String.t()}

  @spec tick_candidate(Types.runtime_state(), Types.surface_target()) :: tick_candidate() | nil
  def tick_candidate(state, target) when is_map(state) and target in [:watch, :companion, :phone] do
    if present?(state, target) do
      state
      |> for_surface(target)
      |> Enum.map(fn command ->
        %{
          trigger: command_trigger_id(command),
          message: command_message(command),
          target: command_target(command)
        }
      end)
      |> Enum.filter(fn row -> row.message != "" end)
      |> Enum.sort_by(&tick_sort_key/1)
      |> List.first()
      |> case do
        %{message: message, trigger: trigger} -> %{message: message, trigger: trigger}
        _ -> nil
      end
    else
      nil
    end
  end

  def tick_candidate(_state, _target), do: nil

  @spec tick_sort_key(Types.trigger_candidate()) :: {integer(), String.t()}
  defp tick_sort_key(%{trigger: trigger, target: target}) when is_binary(trigger) do
    {tick_priority_rank(trigger, target), trigger}
  end

  @spec tick_priority_rank(String.t(), String.t()) :: integer()
  defp tick_priority_rank(trigger, target) when is_binary(trigger) and is_binary(target) do
    trigger_down = String.downcase(trigger)
    target_norm = normalize_target_pattern(target)

    cond do
      frame_subscription_target?(target) -> 0
      String.contains?(target_norm, "second") or String.contains?(trigger_down, "second") -> 1
      String.contains?(target_norm, "minute") or String.contains?(trigger_down, "minute") -> 2
      String.contains?(trigger_down, "tick") or String.contains?(target_norm, "tick") -> 3
      String.contains?(target_norm, "hour") or String.contains?(trigger_down, "hour") -> 4
      true -> 5
    end
  end

  @spec trigger_id_for_command(active_command()) :: String.t()
  def trigger_id_for_command(command) when is_map(command), do: command_trigger_id(command)
  def trigger_id_for_command(_command), do: ""

  @spec trigger_row_from_command(
          active_command(),
          Types.elm_introspect(),
          String.t(),
          (Types.trigger_candidate() -> boolean())
        ) :: Types.trigger_candidate() | nil
  defp trigger_row_from_command(command, ei, target_name, model_active_fn)
       when is_map(command) and is_binary(target_name) do
    catalog = catalog_op_for_command(ei, command)
    trigger = catalog_trigger_id(catalog, command)
    message = command_message(command)

    if trigger == "" or message == "" do
      nil
    else
      label = catalog_label(catalog, trigger)

      trigger_display =
        case catalog do
          %{} = op -> TriggerCandidates.subscription_trigger_display(op, trigger)
          _ -> TriggerCandidates.subscription_trigger_display(%{}, trigger)
        end

      trigger_row = %{trigger: trigger, message: message, target: target_name}

      metadata =
        case catalog do
          %{} = op ->
            op
            |> TriggerCandidates.button_subscription_metadata()
            |> Map.merge(TriggerCandidates.subscription_timing_metadata(op))

          _ ->
            %{}
        end

      interval_ms =
        case Map.get(command, "interval_ms") || Map.get(command, :interval_ms) do
          ms when is_integer(ms) -> TriggerCandidates.clamp_auto_fire_interval_ms(ms)
          _ -> nil
        end

      row = %{
        id: "#{target_name}:#{trigger}:#{TriggerCandidates.normalize_trigger_id(message)}",
        label: label,
        trigger: trigger,
        trigger_display: trigger_display,
        target: target_name,
        message: message,
        source: "subscription",
        model_active: model_active_fn.(trigger_row)
      }

      row =
        if is_integer(interval_ms) do
          Map.put(row, :interval_ms, interval_ms)
        else
          row
        end

      Map.merge(row, metadata)
    end
  end

  defp trigger_row_from_command(_command, _ei, _target_name, _model_active_fn), do: nil

  @spec catalog_trigger_id(Types.cmd_call() | nil, active_command()) :: String.t()
  defp catalog_trigger_id(%{} = catalog, command) do
    case TriggerCandidates.subscription_trigger_for_call(catalog) do
      trigger when is_binary(trigger) and trigger != "" ->
        if frame_subscription_target?(trigger) do
          TriggerCandidates.normalize_trigger_id(trigger)
        else
          subscription_event_kind_from_target(trigger)
        end

      _ ->
        command_trigger_id(command)
    end
  end

  defp catalog_trigger_id(_catalog, command), do: command_trigger_id(command)

  @spec catalog_op_for_command(Types.elm_introspect(), active_command()) ::
          Types.cmd_call() | nil
  defp catalog_op_for_command(ei, command) when is_map(ei) and is_map(command) do
    normalized = normalize_target_pattern(command_target(command))
    message = command_message(command)
    message_ctor = RuntimeModelMessages.wire_constructor(message) || message

    ei
    |> IntrospectAccess.cmd_calls("subscription_calls")
    |> Enum.filter(fn op ->
      op_target = Map.get(op, "target") || Map.get(op, :target) || ""
      op_normalized = normalize_target_pattern(op_target)
      op_normalized == normalized or String.contains?(normalized, op_normalized)
    end)
    |> Enum.find(fn op ->
      callback = Map.get(op, "callback_constructor") || Map.get(op, :callback_constructor) || ""

      callback == message or callback == message_ctor or
        RuntimeModelMessages.wire_constructor(callback) == message_ctor
    end)
    |> case do
      %{} = op -> op
      _ -> nil
    end
  end

  defp catalog_op_for_command(_ei, _command), do: nil

  @spec catalog_label(Types.cmd_call() | nil, String.t()) :: String.t()
  defp catalog_label(%{} = op, trigger) do
    op
    |> Map.get("label")
    |> case do
      label when is_binary(label) and label != "" -> TriggerCandidates.normalize_trigger_label(label)
      _ -> Map.get(op, "name") || trigger
    end
    |> to_string()
  end

  defp catalog_label(_op, trigger), do: trigger

  @spec command_target(active_command()) :: String.t()
  def command_target(command) when is_map(command) do
    command
    |> Map.get("target", Map.get(command, :target))
    |> to_string()
  end

  @spec row_trigger_id(subscription_row_ref()) :: String.t()
  defp row_trigger_id(row) do
    row
    |> TriggerCandidates.row_field(:trigger)
    |> to_string()
    |> TriggerCandidates.normalize_trigger_id()
  end

  @spec row_message(subscription_row_ref()) :: String.t()
  defp row_message(row) do
    row
    |> TriggerCandidates.row_field(:message)
    |> case do
      message when is_binary(message) -> String.trim(message)
      _ -> ""
    end
  end

  @spec command_trigger_id(active_command()) :: String.t()
  defp command_trigger_id(%{"target" => target} = command) when is_binary(target) do
    trigger =
      Map.get(command, "event_kind") ||
        Map.get(command, :event_kind) ||
        if(frame_subscription_target?(target),
          do: target,
          else: subscription_event_kind_from_target(target)
        )

    trigger
    |> to_string()
    |> TriggerCandidates.normalize_trigger_id()
  end

  defp command_trigger_id(command) when is_map(command) do
    case command_target(command) do
      "" ->
        command
        |> TriggerCandidates.subscription_trigger_for_call()
        |> to_string()
        |> TriggerCandidates.normalize_trigger_id()

      target ->
        command_trigger_id(%{"target" => target})
    end
  end

  @spec frame_subscription_target?(String.t()) :: boolean()
  defp frame_subscription_target?(target) when is_binary(target) do
    normalized =
      target
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9.]+/, "")

    String.contains?(normalized, "frame.") or String.ends_with?(normalized, ".onframe") or
      String.ends_with?(normalized, "onframe")
  end

  @spec subscription_event_kind_from_target(String.t()) :: String.t()
  defp subscription_event_kind_from_target(target) when is_binary(target) do
    target
    |> String.split(".")
    |> List.last()
    |> to_string()
    |> String.replace(~r/([a-z])([A-Z])/, "\\1 \\2")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
  end

  @spec messages_compatible?(String.t(), String.t()) :: boolean()
  defp messages_compatible?("", _), do: true
  defp messages_compatible?(_, ""), do: true

  defp messages_compatible?(left, right) when is_binary(left) and is_binary(right) do
    left == right or
      RuntimeModelMessages.wire_constructor(left) == RuntimeModelMessages.wire_constructor(right)
  end

  defp messages_compatible?(_, _), do: false

  @spec triggers_equivalent?(String.t(), String.t()) :: boolean()
  def triggers_equivalent?(left, right) when is_binary(left) and is_binary(right) do
    left == right or companion_triggers_equivalent?(left, right) or
      opaque_gateway_triggers_equivalent?(left, right)
  end

  def triggers_equivalent?(_, _), do: false

  @spec opaque_gateway_triggers_equivalent?(String.t(), String.t()) :: boolean()
  defp opaque_gateway_triggers_equivalent?(left, right) do
    SubscriptionTriggerWire.opaque_gateway_trigger?(left) and
      SubscriptionTriggerWire.opaque_gateway_trigger?(right) and
      opaque_gateway_kind(left) == opaque_gateway_kind(right)
  end

  @spec opaque_gateway_kind(String.t()) :: :phone_to_watch | :watch_to_phone | nil
  defp opaque_gateway_kind(trigger) when is_binary(trigger) do
    normalized =
      trigger
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]/, "")

    cond do
      String.contains?(normalized, "phonetowatch") -> :phone_to_watch
      String.contains?(normalized, "watchtophone") -> :watch_to_phone
      true -> nil
    end
  end

  @spec companion_triggers_equivalent?(String.t(), String.t()) :: boolean()
  defp companion_triggers_equivalent?(left, right) do
    case {CompanionSubscriptionTrigger.contract_for_trigger(left),
          CompanionSubscriptionTrigger.contract_for_trigger(right)} do
      {{:ok, left_contract}, {:ok, right_contract}} ->
        Map.get(left_contract, :source) == Map.get(right_contract, :source)

      _ ->
        false
    end
  end

  @spec target_matches_patterns?(String.t(), [String.t()]) :: boolean()
  defp target_matches_patterns?(target, patterns) when is_binary(target) and is_list(patterns) do
    normalized = normalize_target_pattern(target)
    Enum.any?(patterns, &String.contains?(normalized, &1))
  end

  @spec normalize_target_pattern(String.t()) :: String.t()
  defp normalize_target_pattern(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9.]+/, "")
  end
end
