defmodule Ide.Debugger.TriggerCandidates do
  @moduledoc false

  alias Ide.Debugger.Types
  alias Ide.Debugger.Types.TriggerCandidate

  @default_auto_fire_interval_ms 1_000
  @min_auto_fire_interval_ms 100

  @type model_active_fn :: (TriggerCandidate.t() -> boolean())
  @type button_metadata :: %{
          optional(:button) => String.t(),
          optional(:button_event) => String.t()
        }
  @type timing_metadata :: %{
          optional(:interval_ms) => pos_integer(),
          optional(:declared_interval_ms) => integer()
        }

  alias Ide.Debugger.IntrospectAccess

  @spec row_field(TriggerCandidate.wire_map(), atom()) :: Types.wire_input() | nil
  def row_field(row, key) when is_map(row) and is_atom(key) do
    Map.get(row, key) || Map.get(row, Atom.to_string(key))
  end

  @spec contains_any?(String.t(), [String.t()]) :: boolean()
  defp contains_any?(text, needles) when is_binary(text) and is_list(needles) do
    Enum.any?(needles, &String.contains?(text, &1))
  end

  @spec tickish_message?(String.t()) :: boolean()
  defp tickish_message?(message) when is_binary(message) do
    down = String.downcase(message)

    # Device callback constructors (for example CurrentDateTime) are not subscription ticks.
    not String.contains?(down, "datetime") and
      contains_any?(down, ["tick", "time", "clock", "second", "minute", "hour"])
  end

  @spec message_for_subscription_unit([String.t()], String.t()) :: String.t() | nil
  defp message_for_subscription_unit(known_messages, trigger_down)
       when is_list(known_messages) and is_binary(trigger_down) do
    unit =
      cond do
        contains_any?(trigger_down, ["secondchange", "onsecond"]) or
            (contains_any?(trigger_down, ["second"]) and
               not contains_any?(trigger_down, ["minute"])) ->
          "second"

        contains_any?(trigger_down, ["minutechange", "onminute", "minute"]) ->
          "minute"

        contains_any?(trigger_down, ["hourchange", "onhour", "hour"]) ->
          "hour"

        contains_any?(trigger_down, ["daychange", "onday", "day"]) ->
          "day"

        contains_any?(trigger_down, ["monthchange", "onmonth", "month"]) ->
          "month"

        contains_any?(trigger_down, ["yearchange", "onyear", "year"]) ->
          "year"

        true ->
          nil
      end

    if is_binary(unit) do
      Enum.find(known_messages, fn message ->
        down = String.downcase(message)

        String.contains?(down, unit) and not String.contains?(down, "datetime")
      end)
    end
  end

  @spec normalize_integer(Types.wire_input(), integer()) :: integer()
  defp normalize_integer(value, _default) when is_integer(value), do: value

  defp normalize_integer(value, default) when is_binary(value) and is_integer(default) do
    case Integer.parse(String.trim(value)) do
      {parsed, _} -> parsed
      :error -> default
    end
  end

  defp normalize_integer(_value, default) when is_integer(default), do: default

  @spec for_surface(Types.elm_introspect(), String.t(), model_active_fn()) ::
          [Types.trigger_candidate()]
  def for_surface(ei, target_name, model_active_fn \\ fn _ -> true end)

  def for_surface(ei, target_name, model_active_fn)
      when is_map(ei) and is_binary(target_name) and is_function(model_active_fn, 1) do
    msg_constructors = IntrospectAccess.list(ei, "msg_constructors")
    update_branches = IntrospectAccess.list(ei, "update_case_branches")
    subscription_ops = IntrospectAccess.list(ei, "subscription_ops")
    subscription_calls = IntrospectAccess.cmd_calls(ei, "subscription_calls")
    known_messages = if msg_constructors != [], do: msg_constructors, else: update_branches

    call_rows =
      subscription_calls
      |> Enum.filter(&subscription_call_fireable?/1)
      |> Enum.map(fn op ->
        trigger = subscription_trigger_for_call(op)
        label = Map.get(op, "label") || Map.get(op, "name") || trigger
        callback = Map.get(op, "callback_constructor")
        trigger_id = normalize_trigger_id(trigger)

        message =
          callback ||
            Map.get(trigger_message_index(subscription_calls), trigger_id) ||
            best_message_for_trigger(known_messages, to_string(trigger || "")) ||
            List.first(known_messages) ||
            "Tick"

        metadata =
          op
          |> button_subscription_metadata()
          |> Map.merge(subscription_timing_metadata(op))

        trigger_row = %{
          trigger: to_string(trigger || "trigger"),
          message: message,
          target: target_name
        }

        %{
          id: "#{target_name}:#{trigger_id}:#{normalize_trigger_id(message)}",
          label: normalize_trigger_label(label),
          trigger: trigger_row.trigger,
          trigger_display: subscription_trigger_display(op, trigger),
          target: target_name,
          message: message,
          source: "subscription",
          model_active: model_active_fn.(trigger_row)
        }
        |> Map.merge(metadata)
      end)

    op_rows =
      subscription_ops
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.filter(&subscription_op_fireable?/1)
      |> Enum.map(fn op ->
        message = best_message_for_trigger(known_messages, op)

        %{
          id: "#{target_name}:#{normalize_trigger_id(op)}",
          label: normalize_trigger_label(op),
          trigger: op,
          trigger_display: camel_case_trigger_id(op),
          target: target_name,
          message: message,
          source: "subscription"
        }
      end)

    fallback_rows =
      fallback_trigger_seed_rows(target_name)
      |> Enum.map(fn %{trigger: trigger, label: label} ->
        message = best_message_for_trigger(known_messages, trigger)

        %{
          id: "#{target_name}:#{normalize_trigger_id(trigger)}",
          label: label,
          trigger: trigger,
          trigger_display: camel_case_trigger_id(trigger),
          target: target_name,
          message: message,
          source: "fallback"
        }
      end)

    primary_rows = if call_rows == [], do: op_rows, else: call_rows

    (primary_rows ++ if(primary_rows == [], do: fallback_rows, else: []))
    |> Enum.uniq_by(fn row -> {row.target, row.trigger, row.message} end)
    |> Enum.filter(fn row -> is_binary(row.message) and row.message != "" end)
  end

  def for_surface(_ei, _target_name, _model_active_fn), do: []

  @spec button_subscription_metadata(Types.cmd_call()) :: button_metadata()
  defp button_subscription_metadata(%{"target" => target, "arg_snippets" => [button, event | _]})
       when is_binary(target) and is_binary(button) and is_binary(event) do
    case subscription_target_name(target) do
      "on" ->
        %{
          button: normalize_button_subscription_arg(button),
          button_event: normalize_button_subscription_arg(event)
        }

      name ->
        button_event_metadata(name, button)
    end
  end

  defp button_subscription_metadata(%{"target" => target, "arg_snippets" => [button | _]})
       when is_binary(target) and is_binary(button) do
    button_event_metadata(subscription_target_name(target), button)
  end

  defp button_subscription_metadata(_op), do: %{}

  defp button_event_metadata(target_name, button) do
    case target_name do
      "onPress" ->
        %{button: normalize_button_subscription_arg(button), button_event: "pressed"}

      "onRelease" ->
        %{button: normalize_button_subscription_arg(button), button_event: "released"}

      "onLongPress" ->
        %{button: normalize_button_subscription_arg(button), button_event: "longpressed"}

      _ ->
        %{}
    end
  end

  @spec subscription_timing_metadata(Types.cmd_call()) :: timing_metadata()
  defp subscription_timing_metadata(%{"target" => target, "arg_snippets" => snippets})
       when is_binary(target) and is_list(snippets) do
    if frame_subscription_target?(target) do
      case frame_subscription_interval_ms(target, snippets) do
        interval_ms when is_integer(interval_ms) ->
          %{
            interval_ms: clamp_auto_fire_interval_ms(interval_ms),
            declared_interval_ms: interval_ms
          }

        _ ->
          %{}
      end
    else
      %{}
    end
  end

  defp subscription_timing_metadata(_op), do: %{}

  @spec frame_subscription_interval_ms(String.t(), [Types.wire_map()]) :: integer() | nil
  defp frame_subscription_interval_ms(target, snippets)
       when is_binary(target) and is_list(snippets) do
    value = snippets |> List.first() |> normalize_integer(0)
    target_name = target |> subscription_target_name() |> String.downcase()

    cond do
      value <= 0 ->
        nil

      target_name == "atfps" ->
        div(1_000, max(1, value))

      true ->
        value
    end
  end

  @spec clamp_auto_fire_interval_ms(Types.wire_input()) :: pos_integer()
  def clamp_auto_fire_interval_ms(interval_ms) when is_integer(interval_ms) do
    interval_ms
    |> max(@min_auto_fire_interval_ms)
    |> min(60_000)
  end

  def clamp_auto_fire_interval_ms(_interval_ms), do: @default_auto_fire_interval_ms

  @spec subscription_trigger_for_call(Types.cmd_call()) :: String.t() | nil
  def subscription_trigger_for_call(%{"target" => target} = op) when is_binary(target) do
    if frame_subscription_target?(target) do
      target
    else
      Map.get(op, "event_kind") || Map.get(op, "name") || target
    end
  end

  def subscription_trigger_for_call(%{} = op) do
    Map.get(op, "event_kind") || Map.get(op, "name") || Map.get(op, "target")
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

  @spec subscription_target_name(String.t()) :: String.t()
  defp subscription_target_name(target) when is_binary(target) do
    target
    |> String.split(".")
    |> List.last()
    |> to_string()
  end

  @spec normalize_button_subscription_arg(String.t()) :: String.t()
  defp normalize_button_subscription_arg(value) when is_binary(value) do
    value
    |> String.split(".")
    |> List.last()
    |> to_string()
    |> String.downcase()
  end

  @spec subscription_call_fireable?(Types.cmd_call()) :: boolean()
  defp subscription_call_fireable?(call) when is_map(call) do
    kind =
      call
      |> Map.get("event_kind")
      |> to_string()
      |> String.downcase()

    target =
      call
      |> Map.get("target")
      |> to_string()
      |> String.downcase()

    kind not in ["", "none", "batch"] and
      not String.ends_with?(target, ".none") and
      not String.ends_with?(target, ".batch")
  end

  defp subscription_call_fireable?(_call), do: false

  @spec subscription_op_fireable?(Types.cmd_call()) :: boolean()
  defp subscription_op_fireable?(op) when is_binary(op) do
    normalized =
      op
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "_")
      |> String.trim("_")

    normalized not in ["", "sub_none", "none", "sub_batch", "batch"]
  end

  defp subscription_op_fireable?(_op), do: false

  @spec best_message_for_trigger([String.t()], String.t()) :: String.t() | nil
  def best_message_for_trigger(known_messages, trigger)
      when is_list(known_messages) and is_binary(trigger) do
    normalized = normalize_trigger_id(trigger)

    exact =
      Enum.find(known_messages, fn message ->
        ctor =
          message
          |> to_string()
          |> String.trim()
          |> String.split(~r/\s+/, parts: 2)
          |> List.first()

        is_binary(ctor) and String.downcase(ctor) == normalized
      end)

    exact ||
      message_for_subscription_unit(known_messages, normalized) ||
      message_for_button_trigger(known_messages, normalized) ||
      fallback_message_for_trigger(known_messages, normalized)
  end

  def best_message_for_trigger(_known_messages, _trigger), do: nil

  @spec message_for_button_trigger([String.t()], String.t()) :: String.t() | nil
  defp message_for_button_trigger(known_messages, trigger_down)
       when is_list(known_messages) and is_binary(trigger_down) do
    if contains_any?(trigger_down, ["button", "up", "down", "select", "click"]) do
      Enum.find(known_messages, fn message ->
        down = String.downcase(message)

        String.contains?(down, "button") or String.contains?(down, "press") or
          String.contains?(down, "up") or String.contains?(down, "down")
      end)
    end
  end

  defp message_for_button_trigger(_known_messages, _trigger_down), do: nil

  @spec trigger_message_index([Types.cmd_call()]) :: %{String.t() => String.t()}
  def trigger_message_index(subscription_calls) when is_list(subscription_calls) do
    Enum.reduce(subscription_calls, %{}, fn call, acc ->
      trigger = subscription_trigger_for_call(call)
      callback = Map.get(call, "callback_constructor")

      if is_binary(trigger) and trigger != "" and is_binary(callback) and callback != "" do
        Map.put(acc, normalize_trigger_id(trigger), callback)
      else
        acc
      end
    end)
  end

  @spec first_matching_message([String.t()], [String.t()]) :: String.t() | nil
  defp first_matching_message(known_messages, tokens)
       when is_list(known_messages) and is_list(tokens) do
    Enum.find(known_messages, fn message ->
      down = String.downcase(message)
      Enum.all?(tokens, &String.contains?(down, &1))
    end)
  end

  defp first_matching_message(_known_messages, _tokens), do: nil

  @spec fallback_message_for_trigger([String.t()], String.t()) :: String.t() | nil
  defp fallback_message_for_trigger(known_messages, trigger_down)
       when is_list(known_messages) and is_binary(trigger_down) do
    cond do
      contains_any?(trigger_down, ["up"]) ->
        first_matching_message(known_messages, ["up"]) ||
          first_matching_message(known_messages, ["inc"])

      contains_any?(trigger_down, ["down"]) ->
        first_matching_message(known_messages, ["down"]) ||
          first_matching_message(known_messages, ["dec"])

      contains_any?(trigger_down, ["select", "ok"]) ->
        first_matching_message(known_messages, ["select"]) ||
          first_matching_message(known_messages, ["ok"]) ||
          first_matching_message(known_messages, ["press"])

      contains_any?(trigger_down, ["back"]) ->
        first_matching_message(known_messages, ["back"]) ||
          first_matching_message(known_messages, ["cancel"])

      contains_any?(trigger_down, ["tick", "time", "clock"]) ->
        Enum.find(known_messages, &tickish_message?/1)

      true ->
        nil
    end
  end

  defp fallback_message_for_trigger(_known_messages, _trigger_down), do: nil

  @spec buttonish_trigger?(String.t()) :: boolean()
  defp buttonish_trigger?(trigger_down) when is_binary(trigger_down) do
    contains_any?(trigger_down, ["button", "up", "down", "select", "back", "press", "tap"])
  end

  @spec default_message_for_trigger(String.t()) :: String.t()
  def default_message_for_trigger(trigger) when is_binary(trigger) do
    normalized = String.downcase(trigger)

    if buttonish_trigger?(normalized) do
      trigger
      |> String.split(~r/[^a-zA-Z0-9]+/, trim: true)
      |> Enum.map(&String.capitalize/1)
      |> Enum.join()
      |> case do
        "" -> "ButtonPress"
        value -> value
      end
    else
      "Tick"
    end
  end

  @spec normalize_trigger_id(Types.wire_input()) :: String.t()
  def normalize_trigger_id(trigger) when is_binary(trigger) do
    trigger
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
  end

  def normalize_trigger_id(_), do: "trigger"

  @spec normalize_trigger_label(Types.wire_input()) :: String.t()
  defp normalize_trigger_label(trigger) when is_binary(trigger) do
    trigger
    |> String.replace(~r/[_\.\-]+/, " ")
    |> String.trim()
    |> case do
      "" -> "Trigger"
      value -> value
    end
  end

  defp normalize_trigger_label(_), do: "Trigger"

  @doc false
  @spec subscription_trigger_display(Types.cmd_call() | nil, String.t() | nil) :: String.t()
  def subscription_trigger_display(%{} = op, trigger) do
    case Map.get(op, "target") do
      target when is_binary(target) and target != "" ->
        target

      _ ->
        case subscription_label_name(Map.get(op, "label")) do
          name when is_binary(name) and name != "" -> name
          _ -> camel_case_trigger_id(trigger)
        end
    end
  end

  def subscription_trigger_display(_op, trigger), do: camel_case_trigger_id(trigger)

  @doc false
  @spec subscription_trigger_display_for(Types.elm_introspect(), String.t()) :: String.t()
  def subscription_trigger_display_for(ei, trigger)
      when is_map(ei) and is_binary(trigger) do
    case IntrospectAccess.cmd_calls(ei, "subscription_calls") do
      calls when is_list(calls) ->
        Enum.find_value(calls, fn op ->
          if subscription_trigger_for_call(op) |> to_string() == trigger do
            subscription_trigger_display(op, trigger)
          end
        end) || camel_case_trigger_id(trigger)
    end
  end

  def subscription_trigger_display_for(_ei, trigger) when is_binary(trigger),
    do: camel_case_trigger_id(trigger)

  def subscription_trigger_display_for(_ei, _trigger), do: "Trigger"

  @spec subscription_label_name(String.t() | nil) :: String.t() | nil
  defp subscription_label_name(label) when is_binary(label) do
    case String.split(label, "(", parts: 2) do
      [name, _] ->
        name |> String.trim() |> then(fn value -> if value == "", do: nil, else: value end)

      _ ->
        nil
    end
  end

  defp subscription_label_name(_label), do: nil

  @spec camel_case_trigger_id(String.t() | nil) :: String.t()
  defp camel_case_trigger_id(trigger) when is_binary(trigger) do
    trigger = String.trim(trigger)

    cond do
      trigger == "" ->
        "Trigger"

      String.contains?(trigger, ".") ->
        trigger

      not String.contains?(trigger, "_") ->
        trigger

      true ->
        trigger
        |> String.split("_", trim: true)
        |> case do
          [] ->
            trigger

          [single] ->
            single

          [first | rest] ->
            first <> Enum.map_join(rest, "", &Macro.camelize/1)
        end
    end
  end

  defp camel_case_trigger_id(_trigger), do: "Trigger"

  @spec fallback_trigger_seed_rows(String.t()) :: [Types.trigger_candidate()]
  defp fallback_trigger_seed_rows(target_name) when is_binary(target_name) do
    [
      %{trigger: "button_up", label: "Button Up"},
      %{trigger: "button_long_up", label: "Button Long Up"},
      %{trigger: "button_down", label: "Button Down"},
      %{trigger: "button_long_down", label: "Button Long Down"},
      %{trigger: "button_select", label: "Button Select"},
      %{trigger: "button_long_select", label: "Button Long Select"},
      %{trigger: "button_back", label: "Button Back"},
      %{trigger: "tick", label: "Tick"}
    ]
  end
end
