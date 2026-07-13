defmodule Ide.Test.TemplateElmxElmcParity.Snapshot do
  @moduledoc false

  alias Ide.Mcp.DebuggerTemplateCorpus

  alias Ide.Test.TemplateElmxElmcParity.Types, as: ParityTypes

  @double_quote 34

  @spec from_elmx_step(Ide.Test.TemplateElmxElmcParity.Types.parity_step()) :: Ide.Test.TemplateElmxElmcParity.Types.parity_step()
  def from_elmx_step(%{} = step) do
    step
    |> Map.take(["step_id", "op", "message", "backend", "error"])
    |> Map.put("model", normalize_model(Map.get(step, "model")))
    |> Map.put("view_output", normalize_view_output(Map.get(step, "view_output")))
    |> Map.put("render_tree", normalize_render_tree(Map.get(step, "render_tree")))
    |> Map.put("active_subscriptions", normalize_subscriptions(Map.get(step, "active_subscriptions")))
    |> Map.put("commands", normalize_commands(Map.get(step, "commands")))
  end

  @spec from_elmc_step(Ide.Test.TemplateElmxElmcParity.Types.parity_step()) :: Ide.Test.TemplateElmxElmcParity.Types.parity_step()
  def from_elmc_step(%{} = step) do
    step
    |> Map.update("view_output", [], &normalize_elmc_view_output/1)
    |> from_elmx_step()
  end

  @spec normalize_model(ParityTypes.wire_json_map() | String.t() | nil) ::
          ParityTypes.normalized_model()
  def normalize_model(model) when is_map(model) do
    model
    |> drop_volatile_keys()
    |> normalize_value_map()
  end

  def normalize_model(model) when is_binary(model) do
    model = normalize_debug_model_string(model)

    cond do
      model in ["<model>", "<internals>"] -> %{}
      String.starts_with?(model, "{") -> parse_elmc_debug_record(model)
      true -> model
    end
  end
  def normalize_model(_), do: nil

  @spec normalize_view_output(list() | nil) :: [ParityTypes.normalized_view_row()]
  def normalize_view_output(rows) when is_list(rows) do
    rows
    |> Enum.map(&canonical_preview_op/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&clear_preview_op?/1)
    |> Enum.sort_by(&Jason.encode!/1)
  end

  def normalize_view_output(_), do: []

  @spec normalize_render_tree(ParityTypes.wire_json_map() | nil) :: ParityTypes.wire_json_map()
  def normalize_render_tree(tree) when is_map(tree) do
    tree
    |> Map.take(["root_type", "node_count", "node_types"])
    |> Map.update("node_types", [], fn types ->
      types |> List.wrap() |> Enum.map(&to_string/1) |> Enum.sort()
    end)
  end

  def normalize_render_tree(_), do: %{}

  @spec normalize_subscriptions(list() | integer() | nil) :: [String.t()]
  def normalize_subscriptions(subs) when is_list(subs) do
    subs
    |> Enum.map(&normalize_subscription_entry/1)
    |> Enum.sort()
    |> Enum.uniq()
    |> collapse_zero_subscription_count()
  end

  def normalize_subscriptions(value) when is_integer(value) do
    [Integer.to_string(value)]
  end

  def normalize_subscriptions(_), do: []

  @spec normalize_commands(list() | nil) :: [ParityTypes.wire_json_map()]
  def normalize_commands(cmds) when is_list(cmds) do
    cmds
    |> Enum.map(&normalize_command/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(&Jason.encode!/1)
  end

  def normalize_commands(_), do: []

  @spec normalize_elmc_view_output([Ide.Test.TemplateElmxElmcParity.Types.normalized_view_row()]) :: [Ide.Test.TemplateElmxElmcParity.Types.normalized_view_row()]
  def normalize_elmc_view_output(rows) when is_list(rows) do
    rows
    |> Enum.map(&normalize_elmc_view_row/1)
    |> normalize_view_output()
  end

  defp normalize_elmc_view_row(%{"kind" => kind} = row) when is_integer(kind) do
    kind_name =
      case Elmc.Backend.Pebble.Kinds.Tables.DrawKinds.for_id(kind) do
        nil -> "unknown"
        atom -> atom |> Atom.to_string() |> String.replace("_with_font", "")
      end

    row =
      row
      |> Map.put("kind", kind_name)
      |> Map.new(fn {k, v} -> {to_string(k), v} end)

    infer_elmc_text_label_text(row)
  end

  defp normalize_elmc_view_row(row) when is_map(row), do: row
  defp normalize_elmc_view_row(row), do: row

  # Pebble runtime treats empty text + p3=0 on text_label as WaitingForCompanion.
  defp infer_elmc_text_label_text(%{"kind" => "text_label", "text" => text} = row)
       when text in ["", nil] do
    case Map.get(row, "p3") do
      0 -> Map.put(row, "text", "Waiting for companion app")
      _ -> row
    end
  end

  defp infer_elmc_text_label_text(row), do: row

  @spec corpus_normalize(Ide.Test.TemplateElmxElmcParity.Types.wire_json_map()) :: Ide.Test.TemplateElmxElmcParity.Types.wire_json_map()
  def corpus_normalize(snapshot) when is_map(snapshot) do
    DebuggerTemplateCorpus.normalize_snapshot(snapshot)
  end

  defp canonical_preview_op(op) when is_map(op) do
    kind = op |> Map.get("kind") |> normalize_kind()

    base =
      op
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.put("kind", kind)
      |> Map.drop(["points", "frames", "path"])

    case kind do
      "clear" ->
        base
        |> Map.put("p0", Map.get(base, "p0") || Map.get(base, "color"))
        |> Map.put_new("p1", 0)
        |> Map.put_new("p2", 0)
        |> Map.put_new("text", "")
        |> Map.take(["kind", "p0", "p1", "p2", "text"])

      "vector_sequence_anim" ->
        Map.take(base, ["kind", "vector_id", "x", "y", "frame_count"])

      "unresolved" ->
        Map.take(base, ["kind", "label", "reason"])

      _ ->
        base
    end
  end

  defp canonical_preview_op(_), do: nil

  defp normalize_kind(kind) when is_atom(kind), do: Atom.to_string(kind)
  defp normalize_kind(kind) when is_binary(kind), do: kind
  defp normalize_kind(_), do: "unknown"

  defp collapse_zero_subscription_count([]), do: []
  defp collapse_zero_subscription_count(["0"]), do: []
  defp collapse_zero_subscription_count(subs), do: subs

  defp normalize_subscription_entry(entry) when is_binary(entry), do: entry

  defp normalize_subscription_entry(entry) when is_map(entry) do
    id = Map.get(entry, "id") || Map.get(entry, :id)
    trigger = Map.get(entry, "trigger") || Map.get(entry, :trigger)
    message = Map.get(entry, "message") || Map.get(entry, :message)

    [id, trigger, message]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
    |> Enum.join(":")
  end

  defp normalize_subscription_entry(entry), do: to_string(entry)

  defp normalize_command(cmd) when is_map(cmd) do
    cmd
    |> Map.new(fn {k, v} -> {to_string(k), normalize_value(v)} end)
    |> Map.take(["kind", "message", "target", "trigger", "tag", "interval_ms"])
    |> case do
      %{} = normalized when map_size(normalized) == 0 -> nil
      other -> other
    end
  end

  defp normalize_command(_), do: nil

  defp normalize_debug_model_string(text) when is_binary(text) do
    text
    |> String.replace(~r/\b\d{9,}\b/, "<posix>")
    |> String.replace(~r/RandomGenerated \d+/, "RandomGenerated <seed>")
    |> String.trim()
  end

  @spec model_value_list(ParityTypes.wire_json_map() | String.t() | nil) ::
          [ParityTypes.wire_json_map() | String.t() | number() | boolean()]
  def model_value_list(%{"_values" => values}) when is_list(values), do: values

  def model_value_list(%{} = map) do
    map
    |> Map.values()
    |> Enum.flat_map(fn
      list when is_list(list) -> list
      value -> [value]
    end)
  end

  def model_value_list(model) when is_binary(model) do
    case normalize_model(model) do
      %{"_values" => values} when is_list(values) -> values
      %{} = map -> model_value_list(map)
      _ -> []
    end
  end

  def model_value_list(_), do: []

  defp parse_elmc_debug_record(text) when is_binary(text) do
    inner =
      text
      |> String.trim()
      |> String.trim_leading("{")
      |> String.trim_trailing("}")
      |> String.trim()

    if inner == "" do
      %{}
    else
      if String.contains?(inner, "=") do
        inner
        |> named_debug_record_fields()
        |> normalize_value_map()
      else
        %{"_values" => positional_debug_values(inner)}
      end
    end
  end

  defp named_debug_record_fields(inner) do
    ~r{(\w+)\s*=\s*("[^"]*"|[A-Za-z][A-Za-z0-9_']*|-?\d+)}
    |> Regex.scan(inner)
    |> Map.new(fn [_, key, value] -> {key, parse_debug_value(value)} end)
  end

  defp positional_debug_values(inner) do
    inner
    |> split_debug_commas()
    |> Enum.map(&parse_debug_value/1)
  end

  defp split_debug_commas(text) do
    split_debug_commas(text, 0, false, "", [])
    |> Enum.reverse()
  end

  defp split_debug_commas("", _depth, _in_string, current, acc) do
    case String.trim(current) do
      "" -> acc
      value -> [value | acc]
    end
  end

  defp split_debug_commas(<<char, rest::binary>>, depth, in_string, current, acc) do
    case {char, depth, in_string} do
      {@double_quote, _, false} ->
        split_debug_commas(rest, depth, true, current <> <<char>>, acc)

      {@double_quote, _, true} ->
        split_debug_commas(rest, depth, false, current <> <<char>>, acc)

      {44, 0, false} ->
        split_debug_commas(rest, depth, false, "", finalize_positional_chunk(acc, current))

      {123, _, _} ->
        split_debug_commas(rest, depth + 1, in_string, current <> <<char>>, acc)

      {125, _, _} ->
        split_debug_commas(rest, depth - 1, in_string, current <> <<char>>, acc)

      {40, _, _} ->
        split_debug_commas(rest, depth + 1, in_string, current <> <<char>>, acc)

      {41, _, _} ->
        split_debug_commas(rest, depth - 1, in_string, current <> <<char>>, acc)

      _ ->
        split_debug_commas(rest, depth, in_string, current <> <<char>>, acc)
    end
  end

  defp finalize_positional_chunk(acc, current) do
    case String.trim(current) do
      "" -> acc
      value -> [value | acc]
    end
  end

  defp parse_debug_value(value) when is_binary(value) do
    value = String.trim(value)

    cond do
      value == "True" -> true
      value == "False" -> false
      value == "Nothing" -> %{"ctor" => "Nothing", "args" => []}
      String.starts_with?(value, "Just ") -> %{"ctor" => "Just", "args" => [parse_debug_value(String.trim_leading(value, "Just "))]}
      String.starts_with?(value, "{") -> parse_elmc_debug_record(value)
      Regex.match?(~r/^\x22/, value) -> parse_debug_string(value)
      Regex.match?(~r/^-?\d+$/, value) -> String.to_integer(value)
      Regex.match?(~r/^[A-Z][A-Za-z0-9_']*$/, value) -> %{"ctor" => value, "args" => []}
      true -> value
    end
  end

  defp parse_debug_string(<<@double_quote, rest::binary>>) do
    parse_debug_string_chars(rest, [])
  end

  defp parse_debug_string_chars(<<@double_quote, _::binary>>, acc),
    do: IO.iodata_to_binary(Enum.reverse(acc))

  defp parse_debug_string_chars(<<92, char, rest::binary>>, acc),
    do: parse_debug_string_chars(rest, [char | acc])

  defp parse_debug_string_chars(<<char, rest::binary>>, acc),
    do: parse_debug_string_chars(rest, [char | acc])

  defp clear_preview_op?(%{"kind" => "clear"}), do: true
  defp clear_preview_op?(_), do: false

  defp drop_volatile_keys(model) when is_map(model) do
    Map.drop(model, [
      "active_subscriptions",
      "debugger_contract",
      "debugger_contract_b64",
      "elm_introspect",
      "launch_context",
      "last_path",
      "last_source",
      "last_runtime_step_message",
      "last_runtime_step_op",
      "runtime_execution",
      "runtime_execution_mode",
      "runtime_model_source",
      "runtime_message_cursor",
      "runtime_message_source",
      "runtime_view_tree_source",
      "runtime_known_messages",
      "runtime_update_branches",
      "runtime_view_output",
      "revision",
      "simulator_settings",
      "source_root",
      "status"
    ])
  end

  defp normalize_value_map(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), normalize_value(v)} end)
  end

  defp normalize_value(value) when is_map(value) do
    if Map.has_key?(value, "ctor") or Map.has_key?(value, :ctor) do
      %{
        "ctor" => to_string(Map.get(value, "ctor") || Map.get(value, :ctor)),
        "args" => normalize_value(Map.get(value, "args") || Map.get(value, :args) || [])
      }
    else
      normalize_value_map(value)
    end
  end

  defp normalize_value(value) when is_list(value), do: Enum.map(value, &normalize_value/1)
  defp normalize_value(value) when is_tuple(value), do: value |> Tuple.to_list() |> normalize_value()
  defp normalize_value(value), do: value
end
