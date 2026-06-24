defmodule ElmEx.DebuggerContract.EffectNormalize do
  @moduledoc false

  alias ElmEx.DebuggerContract.CmdCall
  alias ElmEx.DebuggerContract.Types.MsgTagIndex

  @spec normalize_subscription_calls(
          [CmdCall.wire_map()],
          [String.t()],
          MsgTagIndex.t()
        ) :: [CmdCall.wire_map()]
  def normalize_subscription_calls(calls, imports, msg_tag_index)
      when is_list(calls) and is_list(imports) and is_map(msg_tag_index) do
    Enum.map(calls, fn row ->
      row
      |> normalize_target(imports)
      |> normalize_callback(msg_tag_index)
    end)
  end

  def normalize_subscription_calls(calls, imports, _msg_tag_index)
      when is_list(calls) and is_list(imports) do
    Enum.map(calls, &normalize_target(&1, imports))
  end

  def normalize_subscription_calls(calls, _, _), do: calls

  @spec normalize_target(CmdCall.wire_map(), [String.t()]) :: CmdCall.wire_map()
  defp normalize_target(%{"target" => target} = row, imports)
       when is_binary(target) and is_list(imports) do
    Map.put(row, "target", shorten_imported_target(target, imports))
  end

  defp normalize_target(row, _), do: row

  @spec shorten_imported_target(String.t(), [String.t()]) :: String.t()
  defp shorten_imported_target(target, imports) when is_binary(target) and is_list(imports) do
    Enum.reduce(imports, target, fn import_module, acc ->
      shorten_qualified_target(acc, import_module)
    end)
  end

  @spec shorten_qualified_target(String.t(), String.t()) :: String.t()
  defp shorten_qualified_target(target, import_module)
       when is_binary(target) and is_binary(import_module) do
    prefix = import_module <> "."

    if String.starts_with?(target, prefix) do
      alias_name = import_module |> String.split(".") |> List.last() || import_module
      alias_name <> "." <> String.replace_prefix(target, prefix, "")
    else
      target
    end
  end

  @spec normalize_callback(CmdCall.wire_map(), MsgTagIndex.t()) :: CmdCall.wire_map()
  defp normalize_callback(%{"callback_constructor" => nil} = row, msg_tag_index)
       when is_map(msg_tag_index) do
    row
    |> then(fn r ->
      case callback_from_row_args(r, msg_tag_index) do
        ctor when is_binary(ctor) and ctor != "" -> Map.put(r, "callback_constructor", ctor)
        _ -> r
      end
    end)
    |> then(fn
      %{"callback_constructor" => nil, "arg_kinds" => ["int_literal"]} = r ->
        case msg_ctor_for_tagged_literal(r, msg_tag_index) do
          ctor when is_binary(ctor) ->
            name = Map.get(r, "name") || ""

            r
            |> Map.put("callback_constructor", ctor)
            |> Map.put("arg_kinds", ["constructor_call"])
            |> Map.put("arg_snippets", [ctor])
            |> Map.put("label", subscription_label(name, ctor))

          _ ->
            r
        end

      other ->
        other
    end)
  end

  defp normalize_callback(row, _), do: row

  @spec msg_ctor_for_tagged_literal(CmdCall.wire_map(), MsgTagIndex.t()) :: String.t() | nil
  defp msg_ctor_for_tagged_literal(_row, msg_tag_index) when is_map(msg_tag_index) do
    Map.get(msg_tag_index, "1") ||
      Map.get(msg_tag_index, 1) ||
      case Map.values(msg_tag_index) do
        [single] -> single
        _ -> nil
      end
  end

  @spec callback_from_row_args(CmdCall.wire_map(), MsgTagIndex.t()) :: String.t() | nil
  defp callback_from_row_args(%{"arg_values" => values}, msg_tag_index) when is_list(values) do
    Enum.find_value(values, &msg_ctor_from_value(&1, msg_tag_index))
  end

  defp callback_from_row_args(%{"arg_snippets" => [_ | _]}, _msg_tag_index), do: nil
  defp callback_from_row_args(_, _), do: nil

  @spec msg_ctor_from_value(term(), MsgTagIndex.t()) :: String.t() | nil
  defp msg_ctor_from_value(%{"op" => "int_literal", "value" => v}, msg_tag_index),
    do: Map.get(msg_tag_index, to_string(v)) || Map.get(msg_tag_index, v)

  defp msg_ctor_from_value(%{op: :int_literal, value: v}, msg_tag_index),
    do: Map.get(msg_tag_index, to_string(v)) || Map.get(msg_tag_index, v)

  defp msg_ctor_from_value(v, msg_tag_index) when is_integer(v),
    do: Map.get(msg_tag_index, to_string(v)) || Map.get(msg_tag_index, v)

  defp msg_ctor_from_value(%{"op" => "constructor_call", "target" => t}, _msg_tag_index)
       when is_binary(t),
       do: t

  defp msg_ctor_from_value(%{op: :constructor_call, target: t}, _msg_tag_index) when is_binary(t),
    do: t

  defp msg_ctor_from_value(_, _), do: nil

  @spec subscription_label(String.t(), String.t()) :: String.t()
  defp subscription_label(name, ctor) when is_binary(name) and is_binary(ctor) do
    if ctor != "" do
      "#{name}(#{ctor})"
    else
      name
    end
  end

  @spec msg_tag_index_from_unions(ElmEx.CoreIR.Types.Module.wire_t() | map()) :: MsgTagIndex.t()
  def msg_tag_index_from_unions(%{"unions" => unions}) when is_map(unions),
    do: msg_tag_index_from_unions_map(unions)

  def msg_tag_index_from_unions(%{unions: unions}) when is_map(unions),
    do: msg_tag_index_from_unions_map(unions)

  def msg_tag_index_from_unions(_), do: %{}

  @spec msg_tag_index_from_unions_map(map()) :: MsgTagIndex.t()
  defp msg_tag_index_from_unions_map(unions) when is_map(unions) do
    case Map.get(unions, "Msg") || Map.get(unions, :Msg) do
      %{} = msg_union -> build_msg_tag_index(msg_union)
      _ -> %{}
    end
  end

  @spec build_msg_tag_index(map()) :: MsgTagIndex.t()
  defp build_msg_tag_index(msg_union) when is_map(msg_union) do
    tags = Map.get(msg_union, "tags") || Map.get(msg_union, :tags) || %{}

    if map_size(tags) > 0 do
      Map.new(tags, fn {name, tag} -> {to_string(tag), name} end)
    else
      constructors = Map.get(msg_union, "constructors") || Map.get(msg_union, :constructors) || []

      Enum.with_index(constructors, 1)
      |> Map.new(fn
        {%{"name" => name}, idx} -> {to_string(idx), name}
        {%{name: name}, idx} -> {to_string(idx), name}
      end)
    end
  end
end
