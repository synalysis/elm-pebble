defmodule Elmc.Runtime.Executor do
  @moduledoc """
  Experimental in-process runtime executor entrypoint for IDE integration.

  This currently provides deterministic simulation-grade execution output while
  keeping a stable API shape for future full `init`/`update`/`view` execution.
  """

  @type request :: %{
          optional(:source_root) => String.t() | nil,
          optional(:rel_path) => String.t() | nil,
          optional(:source) => String.t() | nil,
          optional(:introspect) => map() | nil,
          optional(:current_model) => map() | nil,
          optional(:current_view_tree) => map() | nil,
          optional(:message) => String.t() | nil,
          optional(:update_branches) => [String.t()] | nil
        }

  @type response :: %{
          model_patch: map(),
          view_tree: map() | nil,
          runtime: map(),
          protocol_events: [map()]
        }

  @dialyzer :no_match
  @spec execute(request()) :: {:ok, response()} | {:error, term()}
  def execute(request) when is_map(request) do
    source_root = map_value(request, :source_root) || "watch"
    rel_path = map_value(request, :rel_path)
    source = map_value(request, :source) || ""
    introspect = map_value(request, :introspect)
    introspect = if is_map(introspect), do: introspect, else: %{}

    current_model = map_value(request, :current_model)
    current_model = if is_map(current_model), do: current_model, else: %{}
    current_view_tree = map_value(request, :current_view_tree)
    current_view_tree = if is_map(current_view_tree), do: current_view_tree, else: %{}
    message = map_value(request, :message)
    update_branches = normalize_update_branches(map_value(request, :update_branches))

    base_runtime_model =
      case map_value(current_model, :runtime_model) do
        model when is_map(model) and map_size(model) > 0 ->
          model

        _ ->
          case map_value(introspect, :init_model) do
            model when is_map(model) -> model
            _ -> %{}
          end
      end

    {runtime_model, runtime_model_source, op} =
      if is_binary(message) and message != "" do
        matched_branch = matching_update_branch(message, update_branches)
        operation = operation_for_message(message, matched_branch)
        init_model = map_value(introspect, :init_model)
        init_model = if is_map(init_model), do: init_model, else: %{}

        updated =
          mutate_runtime_model(base_runtime_model, message, operation, init_model, matched_branch)
          |> Map.put("last_operation", Atom.to_string(operation))
          |> Map.put("last_message", message)

        {updated, "step_message", operation}
      else
        {base_runtime_model, "init_model", nil}
      end

    runtime_view_tree =
      derive_view_tree(current_view_tree, introspect, message, op, source_root, runtime_model)

    view_tree_source = view_tree_source(current_view_tree, introspect, message, runtime_view_tree)

    runtime = %{
      "engine" => "elmc_runtime_executor_v0",
      "source_root" => source_root,
      "rel_path" => rel_path,
      "source_byte_size" => byte_size(source),
      "msg_constructor_count" => list_count(map_value(introspect, :msg_constructors)),
      "update_case_branch_count" => list_count(map_value(introspect, :update_case_branches)),
      "view_case_branch_count" => list_count(map_value(introspect, :view_case_branches)),
      "runtime_model_source" => runtime_model_source,
      "view_tree_source" => view_tree_source,
      "runtime_model_entry_count" => map_size(runtime_model),
      "view_tree_node_count" => view_tree_node_count(runtime_view_tree),
      "runtime_model_sha256" => stable_term_sha256(runtime_model),
      "view_tree_sha256" => stable_term_sha256(runtime_view_tree)
    }

    {:ok,
     %{
       model_patch: %{
         "runtime_model" => runtime_model,
         "runtime_model_source" => runtime_model_source,
         "runtime_model_sha256" => runtime["runtime_model_sha256"],
         "runtime_view_tree_sha256" => runtime["view_tree_sha256"],
         "elm_executor_mode" => "runtime_executed",
         "elm_executor" => runtime
       },
       view_tree: if(map_size(runtime_view_tree) > 0, do: runtime_view_tree, else: nil),
       runtime: runtime,
       protocol_events: []
     }}
  end

  def execute(_), do: {:error, :invalid_execution_request}

  @spec map_value(term(), term()) :: term()
  defp map_value(map, atom_key) when is_map(map) and is_atom(atom_key) do
    Map.get(map, atom_key) || Map.get(map, Atom.to_string(atom_key))
  end

  @spec normalize_update_branches(term()) :: term()
  defp normalize_update_branches(value) when is_list(value) do
    value
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_update_branches(_), do: []

  @spec list_count(term()) :: term()
  defp list_count(value) when is_list(value), do: length(value)
  defp list_count(_), do: 0

  @spec operation_for_message(term(), term()) :: term()
  defp operation_for_message(message, matched_branch) when is_binary(message) do
    branch_op =
      if is_binary(matched_branch),
        do: operation_from_text(matched_branch),
        else: nil

    if is_atom(branch_op) and not is_nil(branch_op),
      do: branch_op,
      else: operation_from_text(message)
  end

  @spec matching_update_branch(term(), term()) :: term()
  defp matching_update_branch(message, update_branches)
       when is_binary(message) and is_list(update_branches) do
    message_ctor = constructor_hint(message)

    if is_binary(message_ctor) do
      Enum.find(update_branches, fn branch ->
        branch_ctor = constructor_hint(branch)
        is_binary(branch_ctor) and String.downcase(branch_ctor) == String.downcase(message_ctor)
      end)
    end
  end

  defp matching_update_branch(_message, _update_branches), do: nil

  @spec constructor_hint(term()) :: term()
  defp constructor_hint(text) when is_binary(text) do
    tokens = message_tokens(text)

    text =
      cond do
        tokens == [] ->
          text

        true ->
          step_idx =
            Enum.find_index(tokens, fn token ->
              String.downcase(token) in ["step", "msg", "message", "event"]
            end)

          cond do
            is_integer(step_idx) and length(tokens) > step_idx + 1 ->
              Enum.at(tokens, step_idx + 1)

            true ->
              text
          end
      end

    candidates =
      Regex.scan(~r/[A-Za-z_][A-Za-z0-9_.]*/, text)
      |> List.flatten()
      |> Enum.reject(fn candidate ->
        String.downcase(candidate) in ["step", "msg", "message", "event"]
      end)

    selected =
      Enum.find(candidates, &constructor_keyword_hint?/1) ||
        List.first(candidates)

    case selected do
      ctor when is_binary(ctor) -> ctor |> String.split(".") |> List.last()
      _ -> nil
    end
  end

  @spec operation_from_text(term()) :: term()
  defp operation_from_text(text) do
    text = to_string(text)
    hint = String.downcase(text)

    cond do
      set_keyword?(hint, text) -> :set
      contains_any?(hint, ["inc", "increment", "up", "plus", "add"]) -> :inc
      contains_any?(hint, ["dec", "decrement", "down", "minus", "sub"]) -> :dec
      contains_any?(hint, ["toggle", "flip", "switch"]) -> :toggle
      contains_any?(hint, ["enable", "enabled", "on", "open", "start"]) -> :enable
      contains_any?(hint, ["disable", "disabled", "off", "close", "stop"]) -> :disable
      contains_any?(hint, ["reset", "clear"]) -> :reset
      true -> :tick
    end
  end

  @spec contains_any?(term(), term()) :: term()
  defp contains_any?(text, needles), do: Enum.any?(needles, &String.contains?(text, &1))

  @spec set_keyword?(term(), term()) :: term()
  defp set_keyword?(hint, text) when is_binary(hint) and is_binary(text) do
    Regex.match?(~r/\b(set|assign|replace)\b/i, hint) or
      String.starts_with?(String.downcase(to_string(constructor_hint(text) || "")), "set")
  end

  @spec mutate_runtime_model(term(), term(), term(), term(), term()) :: term()
  defp mutate_runtime_model(model, message, op, init_model, matched_branch)
       when is_map(model) and is_binary(message) and is_atom(op) and is_map(init_model) do
    {numeric_key, bool_key} = resolve_target_keys(model, message, matched_branch)
    preferred_set_type = branch_set_payload_type(matched_branch)

    updated =
      case op do
        :inc ->
          mutate_selected_numeric(model, numeric_key, fn value -> value + 1 end)

        :dec ->
          mutate_selected_numeric(model, numeric_key, fn value -> value - 1 end)

        :reset ->
          model
          |> reset_selected_numeric(numeric_key, init_model)
          |> reset_selected_boolean(bool_key, init_model)

        :toggle ->
          mutate_selected_boolean(model, bool_key, fn value -> !value end)

        :enable ->
          mutate_selected_boolean(model, bool_key, fn _value -> true end)

        :disable ->
          mutate_selected_boolean(model, bool_key, fn _value -> false end)

        :set ->
          apply_set_mutation(model, numeric_key, bool_key, message, preferred_set_type)

        _ ->
          model
      end

    if updated != model do
      updated
    else
      Map.put(model, "step_counter", (map_value(model, :step_counter) || 0) + 1)
    end
  end

  @spec resolve_target_keys(term(), term(), term()) :: term()
  defp resolve_target_keys(model, message, matched_branch)
       when is_map(model) and is_binary(message) do
    fallback_numeric = primary_numeric_key(model)
    fallback_bool = primary_boolean_key(model)

    hint = model_key_hint_from_branch_or_message(matched_branch, message)

    hinted_numeric = hinted_model_key(model, hint, :integer)
    hinted_bool = hinted_model_key(model, hint, :boolean)

    {
      hinted_numeric || fallback_numeric,
      hinted_bool || fallback_bool
    }
  end

  @spec model_key_hint_from_branch_or_message(term(), term()) :: term()
  defp model_key_hint_from_branch_or_message(matched_branch, message)
       when is_binary(message) do
    ctor =
      cond do
        is_binary(matched_branch) ->
          constructor_hint(matched_branch)

        true ->
          constructor_hint(message)
      end

    extract_key_hint_from_constructor(ctor)
  end

  @spec extract_key_hint_from_constructor(term()) :: term()
  defp extract_key_hint_from_constructor(ctor) when is_binary(ctor) do
    lower = String.downcase(ctor)

    key_hint =
      cond do
        String.starts_with?(lower, "set") -> strip_constructor_prefix(ctor, 3)
        String.starts_with?(lower, "increment") -> strip_constructor_prefix(ctor, 9)
        String.starts_with?(lower, "decrement") -> strip_constructor_prefix(ctor, 9)
        String.starts_with?(lower, "inc") -> strip_constructor_prefix(ctor, 3)
        String.starts_with?(lower, "dec") -> strip_constructor_prefix(ctor, 3)
        String.starts_with?(lower, "toggle") -> strip_constructor_prefix(ctor, 6)
        String.starts_with?(lower, "enable") -> strip_constructor_prefix(ctor, 6)
        String.starts_with?(lower, "disable") -> strip_constructor_prefix(ctor, 7)
        String.starts_with?(lower, "reset") -> strip_constructor_prefix(ctor, 5)
        true -> nil
      end

    case key_hint do
      nil ->
        nil

      text ->
        text = String.trim(to_string(text))
        if text == "", do: nil, else: text
    end
  end

  defp extract_key_hint_from_constructor(_), do: nil

  @spec strip_constructor_prefix(term(), term()) :: term()
  defp strip_constructor_prefix(ctor, prefix_len)
       when is_binary(ctor) and is_integer(prefix_len) and prefix_len >= 0 do
    total = String.length(ctor)
    len = max(total - prefix_len, 0)
    String.slice(ctor, prefix_len, len)
  end

  @spec hinted_model_key(term(), term(), term()) :: term()
  defp hinted_model_key(_model, nil, _type), do: nil

  defp hinted_model_key(model, hint, :integer) when is_map(model) and is_binary(hint) do
    find_matching_model_key(model, hint, fn value -> is_integer(value) end)
  end

  defp hinted_model_key(model, hint, :boolean) when is_map(model) and is_binary(hint) do
    find_matching_model_key(model, hint, fn value -> is_boolean(value) end)
  end

  @spec find_matching_model_key(term(), term(), term()) :: term()
  defp find_matching_model_key(model, hint, value_predicate)
       when is_map(model) and is_binary(hint) and is_function(value_predicate, 1) do
    hint_norm = normalize_identifier(hint)

    model
    |> Enum.reject(fn {key, value} ->
      bookkeeping_model_key?(key) or not value_predicate.(value)
    end)
    |> Enum.find_value(fn {key, _value} ->
      key_norm = key |> to_string() |> normalize_identifier()

      if key_norm == hint_norm or
           String.starts_with?(key_norm, hint_norm) or
           String.ends_with?(key_norm, hint_norm) do
        key
      end
    end)
  end

  @spec normalize_identifier(term()) :: term()
  defp normalize_identifier(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]/, "")
  end

  @spec apply_set_mutation(term(), term(), term(), term(), term()) :: term()
  defp apply_set_mutation(model, numeric_key, bool_key, message, preferred_set_type)
       when is_map(model) and is_binary(message) do
    case preferred_set_type do
      :int ->
        set_selected_numeric_from_message(model, numeric_key, message)

      :bool ->
        set_selected_boolean_from_message(model, bool_key, message)

      _ ->
        model
        |> set_selected_numeric_from_message(numeric_key, message)
        |> set_selected_boolean_from_message(bool_key, message)
    end
  end

  @spec branch_set_payload_type(term()) :: term()
  defp branch_set_payload_type(branch) when is_binary(branch) do
    hint = String.downcase(branch)

    cond do
      Regex.match?(~r/\bbool\b/, hint) -> :bool
      Regex.match?(~r/\bint\b/, hint) -> :int
      true -> nil
    end
  end

  defp branch_set_payload_type(_), do: nil

  @spec primary_numeric_key(term()) :: term()
  defp primary_numeric_key(model) when is_map(model) do
    keys =
      Enum.filter(Map.keys(model), fn key ->
        is_integer(Map.get(model, key)) and not bookkeeping_model_key?(key)
      end)

    preferred_key(keys, ["n", "count", "counter", "value", "index", "total", "q", "p"])
  end

  @spec primary_boolean_key(term()) :: term()
  defp primary_boolean_key(model) when is_map(model) do
    keys =
      Enum.filter(Map.keys(model), fn key ->
        is_boolean(Map.get(model, key)) and not bookkeeping_model_key?(key)
      end)

    preferred_key(keys, ["enabled", "active", "on", "open", "visible", "toggled", "flag"])
  end

  @spec bookkeeping_model_key?(term()) :: term()
  defp bookkeeping_model_key?(key) do
    key_text =
      key
      |> to_string()
      |> String.downcase()

    String.starts_with?(key_text, "_") or
      key_text in [
        "step_counter",
        "protocol_inbound_count",
        "protocol_message_count",
        "runtime_model_entry_count",
        "view_tree_node_count"
      ]
  end

  @spec preferred_key(term(), term()) :: term()
  defp preferred_key([], _preferred), do: nil

  defp preferred_key(keys, preferred_names) when is_list(keys) and is_list(preferred_names) do
    normalized =
      keys
      |> Enum.map(fn key -> {key, key |> to_string() |> String.downcase()} end)

    Enum.find_value(preferred_names, fn preferred ->
      Enum.find_value(normalized, fn {key, text} -> if text == preferred, do: key end)
    end) ||
      normalized
      |> Enum.sort_by(fn {_key, text} -> text end)
      |> List.first()
      |> case do
        {key, _} -> key
        _ -> nil
      end
  end

  @spec set_selected_numeric_from_message(term(), term(), term()) :: term()
  defp set_selected_numeric_from_message(model, nil, _message), do: model

  defp set_selected_numeric_from_message(model, key, message)
       when is_map(model) and is_binary(message) do
    value = Map.get(model, key)

    case {is_integer(value), message_integer_value(message, key)} do
      {true, int} when is_integer(int) ->
        Map.put(model, key, int)

      _ ->
        model
    end
  end

  @spec set_selected_boolean_from_message(term(), term(), term()) :: term()
  defp set_selected_boolean_from_message(model, nil, _message), do: model

  defp set_selected_boolean_from_message(model, key, message)
       when is_map(model) and is_binary(message) do
    value = Map.get(model, key)

    case {is_boolean(value), message_boolean_value(message, key)} do
      {true, bool} when is_boolean(bool) ->
        Map.put(model, key, bool)

      _ ->
        model
    end
  end

  @spec message_integer_value(term(), term()) :: term()
  defp message_integer_value(message, key) when is_binary(message) do
    key_text =
      key
      |> to_string()
      |> Regex.escape()

    key_pattern = ~r/\b#{key_text}\b\s*=\s*(-?\d+)/i

    payload_segments = message_payload_segments(message)
    constructor_tail = constructor_tail_for_message(message)
    constructor_full_tail = constructor_full_tail_for_message(message)
    scoped_segments = payload_scope_segments(payload_segments, constructor_tail, 2)
    wrapped_from_tail = wrapped_integer_value(constructor_tail)

    scoped_segments
    |> Enum.find_value(fn segment ->
      case Regex.run(key_pattern, segment, capture: :all_but_first) do
        [digits] ->
          case Integer.parse(digits) do
            {int, _} -> int
            _ -> nil
          end

        _ ->
          nil
      end
    end)
    |> case do
      int when is_integer(int) ->
        int

      _ ->
        wrapped_from_tail ||
          Enum.find_value(Enum.reverse(scoped_segments), fn segment ->
            segment
            |> constructor_tail_argument_window(2)
            |> wrapped_integer_value()
          end) ||
          Enum.find_value(Enum.reverse(scoped_segments), &extract_integer_from_tail/1) ||
          extract_integer_from_head(constructor_full_tail) ||
          extract_integer_from_tail(constructor_full_tail) ||
          extract_integer_from_tail(message) ||
          extract_integer(message)
    end
  end

  @spec message_boolean_value(term(), term()) :: term()
  defp message_boolean_value(message, key) when is_binary(message) do
    key_text =
      key
      |> to_string()
      |> Regex.escape()

    key_pattern = ~r/\b#{key_text}\b\s*=\s*(true|false|on|off|enable|enabled|disable|disabled)\b/i
    constructor_tail = constructor_tail_for_message(message)
    constructor_full_tail = constructor_full_tail_for_message(message)
    payload_segments = message_payload_segments(message)
    scoped_segments = payload_scope_segments(payload_segments, constructor_tail, 2)
    wrapped_from_tail = wrapped_boolean_value(constructor_tail)

    payload_bool =
      Enum.reduce_while(scoped_segments, nil, fn segment, _acc ->
        explicit =
          case Regex.run(key_pattern, segment, capture: :all_but_first) do
            [token] -> boolean_token_value(token)
            _ -> nil
          end

        value =
          if is_boolean(explicit),
            do: explicit,
            else:
              segment
              |> constructor_tail_argument_window(2)
              |> wrapped_boolean_value()

        if is_boolean(value), do: {:halt, value}, else: {:cont, nil}
      end)

    if is_boolean(payload_bool),
      do: payload_bool,
      else:
        first_boolean_value([
          wrapped_from_tail,
          first_boolean_from_segments(Enum.reverse(scoped_segments), fn segment ->
            segment
            |> constructor_tail_argument_window(2)
            |> wrapped_boolean_value()
          end),
          first_boolean_from_segments(
            Enum.reverse(scoped_segments),
            &boolean_token_value_from_tail/1
          ),
          boolean_token_value_from_head(constructor_full_tail),
          boolean_token_value_from_tail(constructor_full_tail),
          boolean_token_value(message)
        ])
  end

  @spec message_payload_segments(term()) :: term()
  defp message_payload_segments(message) when is_binary(message) do
    tokens = message_tokens(message)
    ctor = constructor_hint(message)

    step_idx =
      Enum.find_index(tokens, fn token ->
        String.downcase(token) in ["step", "msg", "message", "event"]
      end)

    ctor_idx =
      if is_binary(ctor) do
        Enum.find_index(tokens, &constructor_token_matches?(&1, ctor))
      end

    cond do
      is_integer(step_idx) and length(tokens) > step_idx + 2 ->
        Enum.drop(tokens, step_idx + 2)

      is_integer(ctor_idx) ->
        ctor_token = Enum.at(tokens, ctor_idx) || ""

        ctor_tail =
          payload_after_constructor_token(ctor_token, ctor)
          |> String.trim()

        trailing_tokens =
          tokens
          |> Enum.drop(ctor_idx + 1)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        [ctor_tail | trailing_tokens]
        |> Enum.reject(&(&1 == ""))

      length(tokens) > 1 ->
        [_ctor | rest] = tokens
        rest

      true ->
        case ctor do
          ctor when is_binary(ctor) ->
            constructor_payload_tail_segments(message, ctor)

          _ ->
            []
        end
    end
  end

  @spec constructor_token_matches?(term(), term()) :: term()
  defp constructor_token_matches?(token, ctor) when is_binary(token) and is_binary(ctor) do
    escaped = Regex.escape(ctor)
    pattern = ~r/\b(?:[A-Za-z_][A-Za-z0-9_]*\.)*#{escaped}\b/i
    Regex.match?(pattern, token)
  end

  @spec payload_after_constructor_token(term(), term()) :: term()
  defp payload_after_constructor_token(token, ctor) when is_binary(token) and is_binary(ctor) do
    escaped = Regex.escape(ctor)
    pattern = ~r/\b(?:[A-Za-z_][A-Za-z0-9_]*\.)*#{escaped}\b(?<tail>.*)$/i

    case Regex.named_captures(pattern, token) do
      %{"tail" => tail} -> tail
      _ -> ""
    end
  end

  @spec message_tokens(term()) :: term()
  defp message_tokens(message) when is_binary(message) do
    message
    |> String.split(":")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  @spec constructor_payload_tail_segments(term(), term()) :: term()
  defp constructor_payload_tail_segments(message, ctor)
       when is_binary(message) and is_binary(ctor) do
    escaped = Regex.escape(ctor)

    pattern =
      ~r/\b(?:[A-Za-z_][A-Za-z0-9_]*\.)*#{escaped}\b(?<tail>.*)$/i

    case Regex.named_captures(pattern, message) do
      %{"tail" => tail} ->
        tail =
          tail
          |> String.trim()

        if tail == "", do: [], else: [tail]

      _ ->
        []
    end
  end

  @spec constructor_tail_for_message(term()) :: term()
  defp constructor_tail_for_message(message) when is_binary(message) do
    case constructor_hint(message) do
      ctor when is_binary(ctor) ->
        message
        |> constructor_payload_tail_segments(ctor)
        |> List.first()
        |> case do
          tail when is_binary(tail) -> constructor_tail_argument_window(tail, 2)
          _ -> ""
        end

      _ ->
        ""
    end
  end

  @spec constructor_full_tail_for_message(term()) :: term()
  defp constructor_full_tail_for_message(message) when is_binary(message) do
    case constructor_hint(message) do
      ctor when is_binary(ctor) ->
        message
        |> constructor_payload_tail_segments(ctor)
        |> List.first()
        |> case do
          tail when is_binary(tail) -> String.trim(tail)
          _ -> ""
        end

      _ ->
        ""
    end
  end

  @spec constructor_tail_argument_window(term(), term()) :: term()
  defp constructor_tail_argument_window(text, max_args)
       when is_binary(text) and is_integer(max_args) and max_args > 0 do
    text
    |> String.trim()
    |> take_leading_arguments(max_args, [])
    |> Enum.join(" ")
    |> String.trim()
  end

  @spec payload_scope_segments(term(), term(), term()) :: term()
  defp payload_scope_segments(payload_segments, constructor_tail, max_args)
       when is_list(payload_segments) and is_binary(constructor_tail) and is_integer(max_args) do
    [constructor_tail | payload_segments]
    |> Enum.map(&constructor_tail_argument_window(&1, max_args))
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  @spec take_leading_arguments(term(), term(), term()) :: term()
  defp take_leading_arguments("", _max_args, acc), do: Enum.reverse(acc)
  defp take_leading_arguments(_text, 0, acc), do: Enum.reverse(acc)

  defp take_leading_arguments(text, max_args, acc)
       when is_binary(text) and is_integer(max_args) do
    {arg, rest} = take_single_argument(text)

    if arg == "" do
      Enum.reverse(acc)
    else
      take_leading_arguments(String.trim_leading(rest), max_args - 1, [arg | acc])
    end
  end

  @spec take_single_argument(term()) :: term()
  defp take_single_argument(<<first, _::binary>> = text) when first in [?(, ?[, ?{] do
    take_group_argument(text)
  end

  defp take_single_argument(text) when is_binary(text) do
    case Regex.run(~r/^(\S+)(?:\s+(.*))?$/s, text, capture: :all_but_first) do
      [arg, rest] -> {arg, rest}
      [arg] -> {arg, ""}
      _ -> {"", ""}
    end
  end

  @spec take_group_argument(term()) :: term()
  defp take_group_argument(<<open, rest::binary>>) when open in [?(, ?[, ?{] do
    closer = matching_closer(open)
    consume_group(rest, [closer], <<open>>, "")
  end

  @spec consume_group(term(), term(), term(), term()) :: term()
  defp consume_group(<<>>, _stack, acc, _last_rest), do: {acc, ""}

  defp consume_group(rest, [], acc, _last_rest), do: {acc, rest}

  defp consume_group(<<char, tail::binary>> = rest, [char | stack_rest], acc, _last_rest) do
    acc = <<acc::binary, char>>

    if stack_rest == [] do
      {acc, tail}
    else
      consume_group(tail, stack_rest, acc, rest)
    end
  end

  defp consume_group(<<char, tail::binary>> = rest, stack, acc, _last_rest) do
    next_stack =
      case matching_closer(char) do
        nil -> stack
        closer -> [closer | stack]
      end

    consume_group(tail, next_stack, <<acc::binary, char>>, rest)
  end

  @spec matching_closer(term()) :: term()
  defp matching_closer(?(), do: ?)
  defp matching_closer(?[), do: ?]
  defp matching_closer(?{), do: ?}
  defp matching_closer(_), do: nil

  @spec constructor_keyword_hint?(term()) :: term()
  defp constructor_keyword_hint?(text) when is_binary(text) do
    lowered = String.downcase(text)

    contains_any?(lowered, [
      "set",
      "inc",
      "dec",
      "toggle",
      "reset",
      "enable",
      "disable",
      "up",
      "down"
    ])
  end

  @spec extract_integer(term()) :: term()
  defp extract_integer(text) when is_binary(text) do
    case Regex.run(~r/-?\d+/, text) do
      [digits] ->
        case Integer.parse(digits) do
          {int, _} -> int
          _ -> nil
        end

      _ ->
        nil
    end
  end

  @spec extract_integer_from_tail(term()) :: term()
  defp extract_integer_from_tail(text) when is_binary(text) do
    matches = Regex.scan(~r/-?\d+/, text) |> List.flatten()

    case List.last(matches) do
      digits when is_binary(digits) ->
        case Integer.parse(digits) do
          {int, _} -> int
          _ -> nil
        end

      _ ->
        nil
    end
  end

  @spec extract_integer_from_head(term()) :: term()
  defp extract_integer_from_head(text) when is_binary(text) do
    case Regex.run(~r/-?\d+/, text) do
      [digits] ->
        case Integer.parse(digits) do
          {int, _} -> int
          _ -> nil
        end

      _ ->
        nil
    end
  end

  @spec wrapped_integer_value(term()) :: term()
  defp wrapped_integer_value(text) when is_binary(text) do
    case Regex.scan(~r/\b(?:just|ok|value)\b[^-0-9]*(?<digits>-?\d+)/i, text, capture: :all_names) do
      [] ->
        nil

      matches ->
        matches
        |> List.last()
        |> case do
          [digits] ->
            case Integer.parse(digits) do
              {int, _} -> int
              _ -> nil
            end

          _ ->
            nil
        end
    end
  end

  @spec boolean_token_value(term()) :: term()
  defp boolean_token_value(text) when is_binary(text) do
    hint = String.downcase(text)

    cond do
      Regex.match?(~r/\btrue\b/i, hint) -> true
      Regex.match?(~r/\bfalse\b/i, hint) -> false
      Regex.match?(~r/\boff\b/i, hint) -> false
      Regex.match?(~r/\bon\b/i, hint) -> true
      Regex.match?(~r/\bdisable(d)?\b/i, hint) -> false
      Regex.match?(~r/\benable(d)?\b/i, hint) -> true
      true -> nil
    end
  end

  @spec boolean_token_value_from_tail(term()) :: term()
  defp boolean_token_value_from_tail(text) when is_binary(text) do
    tokens =
      Regex.scan(~r/\b(true|false|on|off|enable|enabled|disable|disabled)\b/i, text,
        capture: :all_but_first
      )
      |> List.flatten()

    case List.last(tokens) do
      token when is_binary(token) -> boolean_token_value(token)
      _ -> nil
    end
  end

  @spec boolean_token_value_from_head(term()) :: term()
  defp boolean_token_value_from_head(text) when is_binary(text) do
    tokens =
      Regex.scan(~r/\b(true|false|on|off|enable|enabled|disable|disabled)\b/i, text,
        capture: :all_but_first
      )
      |> List.flatten()

    case List.first(tokens) do
      token when is_binary(token) -> boolean_token_value(token)
      _ -> nil
    end
  end

  @spec first_boolean_value(term()) :: term()
  defp first_boolean_value(values) when is_list(values) do
    Enum.find(values, &is_boolean/1)
  end

  @spec first_boolean_from_segments(term(), term()) :: term()
  defp first_boolean_from_segments(segments, extractor)
       when is_list(segments) and is_function(extractor, 1) do
    Enum.reduce_while(segments, nil, fn segment, _acc ->
      value = extractor.(segment)
      if is_boolean(value), do: {:halt, value}, else: {:cont, nil}
    end)
  end

  @spec wrapped_boolean_value(term()) :: term()
  defp wrapped_boolean_value(text) when is_binary(text) do
    case Regex.scan(
           ~r/\b(?:just|ok|value)\b[^A-Za-z]*(true|false|on|off|enable|enabled|disable|disabled)\b/i,
           text,
           capture: :all_but_first
         ) do
      [] ->
        nil

      matches ->
        matches
        |> List.last()
        |> List.last()
        |> case do
          token when is_binary(token) -> boolean_token_value(token)
          _ -> nil
        end
    end
  end

  @spec mutate_selected_numeric(term(), term(), term()) :: term()
  defp mutate_selected_numeric(model, nil, _fun), do: model

  defp mutate_selected_numeric(model, key, fun) when is_map(model) and is_function(fun, 1) do
    value = Map.get(model, key)
    if is_integer(value), do: Map.put(model, key, fun.(value)), else: model
  end

  @spec mutate_selected_boolean(term(), term(), term()) :: term()
  defp mutate_selected_boolean(model, nil, _fun), do: model

  defp mutate_selected_boolean(model, key, fun) when is_map(model) and is_function(fun, 1) do
    value = Map.get(model, key)
    if is_boolean(value), do: Map.put(model, key, fun.(value)), else: model
  end

  @spec reset_selected_numeric(term(), term(), term()) :: term()
  defp reset_selected_numeric(model, nil, _init_model), do: model

  defp reset_selected_numeric(model, key, init_model) when is_map(model) and is_map(init_model) do
    reset_to =
      case Map.get(init_model, key) do
        value when is_integer(value) -> value
        _ -> 0
      end

    value = Map.get(model, key)
    if is_integer(value), do: Map.put(model, key, reset_to), else: model
  end

  @spec reset_selected_boolean(term(), term(), term()) :: term()
  defp reset_selected_boolean(model, nil, _init_model), do: model

  defp reset_selected_boolean(model, key, init_model) when is_map(model) and is_map(init_model) do
    init_value = Map.get(init_model, key)
    reset_to = if is_boolean(init_value), do: init_value, else: false

    value = Map.get(model, key)
    if is_boolean(value), do: Map.put(model, key, reset_to), else: model
  end

  @spec derive_view_tree(term(), term(), term(), term(), term(), term()) :: term()
  defp derive_view_tree(current_view_tree, introspect, message, op, source_root, runtime_model) do
    introspect_view =
      case map_value(introspect, :view_tree) do
        tree when is_map(tree) -> tree
        _ -> %{"type" => "root", "children" => []}
      end

    base =
      cond do
        not (is_binary(message) and message != "") ->
          introspect_view

        is_map(current_view_tree) and map_size(current_view_tree) > 0 ->
          current_view_tree

        true ->
          introspect_view
      end

    if is_binary(message) and is_atom(op) do
      children =
        case Map.get(base, "children") || Map.get(base, :children) do
          xs when is_list(xs) -> xs
          _ -> []
        end

      marker = %{
        "type" => "elmcRuntimeStep",
        "label" => "#{source_root}:#{message}",
        "op" => Atom.to_string(op),
        "model_entries" => map_size(runtime_model),
        "children" => []
      }

      base
      |> Map.put("children", [marker | children] |> Enum.take(12))
      |> Map.put("last_runtime_step_message", message)
      |> Map.put("last_runtime_step_op", Atom.to_string(op))
    else
      base
    end
  end

  @spec view_tree_source(term(), term(), term(), term()) :: term()
  defp view_tree_source(current_view_tree, introspect, message, runtime_view_tree)
       when is_map(runtime_view_tree) do
    cond do
      map_size(runtime_view_tree) == 0 ->
        "none"

      is_binary(message) and message != "" ->
        "step_derived_view_tree"

      is_map(map_value(introspect, :view_tree)) ->
        "parser_view_tree"

      is_map(current_view_tree) and map_size(current_view_tree) > 0 ->
        "existing_view_tree"

      true ->
        "elmc_runtime_view_tree"
    end
  end

  @spec view_tree_node_count(term()) :: term()
  defp view_tree_node_count(%{"children" => children}) when is_list(children) do
    1 +
      Enum.reduce(children, 0, fn child, acc ->
        if is_map(child), do: acc + view_tree_node_count(child), else: acc
      end)
  end

  defp view_tree_node_count(%{children: children}) when is_list(children) do
    1 +
      Enum.reduce(children, 0, fn child, acc ->
        if is_map(child), do: acc + view_tree_node_count(child), else: acc
      end)
  end

  defp view_tree_node_count(%{}), do: 1
  defp view_tree_node_count(_), do: 0

  @spec stable_term_sha256(term()) :: term()
  defp stable_term_sha256(term) do
    :crypto.hash(:sha256, :erlang.term_to_binary(term))
    |> Base.encode16(case: :lower)
  end
end
