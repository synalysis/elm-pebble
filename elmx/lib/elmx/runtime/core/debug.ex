defmodule Elmx.Runtime.Core.Debug do
  @moduledoc false

  alias Elmx.Types

  require Logger

  @doc "Elm `Debug.log` — returns `value` unchanged after logging."
  @spec log(Types.string_like() | term(), value) :: value when value: var
  def log(label, value) do
    Logger.debug(fn -> "#{inspect(label)}: #{inspect(value)}" end)
    value
  end

  @spec todo(Types.string_like() | term()) :: no_return()
  def todo(label), do: raise "Debug.todo: #{inspect(label)}"

  @spec to_string(Types.string_like() | Types.wire_input()) :: String.t()
  def to_string(value), do: format_value(value)

  defp format_value(value) do
    case wire_shape(value) do
      {:char, code} -> format_char_literal(code)

      {:ctor, "Char", [arg]} ->
        "Char " <> format_char_payload(arg)

      {:ctor, name, []} -> name
      {:ctor, name, args} -> name <> " " <> Enum.map_join(args, " ", &format_value/1)

      {:dict, items} ->
        sorted =
          Enum.sort(items, fn {ka, _}, {kb, _} ->
            case Elmx.Runtime.Core.basics_compare(ka, kb) do
              :LT -> true
              _ -> false
            end
          end)

        "HashMap.fromList [" <>
          Enum.map_join(sorted, ",", fn {k, v} ->
            "(" <> format_value(k) <> "," <> format_value(v) <> ")"
          end) <> "]"

      {:set, items} ->
        sorted =
          Enum.sort(items, fn ka, kb ->
            case Elmx.Runtime.Core.basics_compare(ka, kb) do
              :LT -> true
              _ -> false
            end
          end)

        "Set.fromList [" <> Enum.map_join(sorted, ",", &format_value/1) <> "]"

      {:tuple, first, rest} ->
        "(" <> format_tuple_spine(first, rest) <> ")"

      {:list, items} ->
        "[" <> Enum.map_join(items, ",", &format_value/1) <> "]"

      {:record, fields} ->
        if fields == [] do
          "{}"
        else
          "{ " <> record_fields_to_string(fields) <> " }"
        end

      {:manager, map} ->
        format_manager(map)

      {:union_spine, cells} ->
        "(" <> Enum.map_join(cells, ",", &format_value/1) <> ")"

      {:task, label} -> label

      :plain -> plain_to_string(value)
    end
  end

  defp wire_shape({:elmx_task, kind, payload}), do: {:task, task_debug_label(kind, payload)}

  defp wire_shape({:elmx_set, items}) when is_list(items), do: {:set, items}
  defp wire_shape({:elmx_dict, items}) when is_map(items),
    do: {:dict, Map.to_list(items)}

  defp wire_shape({:elmx_dict, items}) when is_list(items), do: {:dict, items}
  defp wire_shape({:elmx_char, code}) when is_integer(code), do: {:char, code}

  defp wire_shape(%{"$" => _} = manager) when is_map(manager), do: {:manager, manager}

  defp wire_shape(%{"ctor" => ctor, "args" => args}) when is_binary(ctor) and is_list(args),
    do: {:ctor, ctor, args}

  defp wire_shape(%{ctor: ctor, args: args}) when is_atom(ctor) and is_list(args),
    do: {:ctor, Atom.to_string(ctor), args}

  defp wire_shape({ctor, args}) when is_atom(ctor) and is_list(args),
    do: {:ctor, Atom.to_string(ctor), args}

  defp wire_shape(tuple) when is_tuple(tuple) do
    case Tuple.to_list(tuple) do
      [a, b] when is_atom(a) and is_atom(b) ->
        if union_ctor_atom?(a) and union_ctor_atom?(b) do
          tuple_spine_shape(tuple)
        else
          union_tuple_shape([a | [b]])
        end

      [a, b] when is_atom(a) and is_tuple(b) and tuple_size(b) == 2 ->
        cond do
          union_ctor_atom?(a) and union_ctor_atom?(elem(b, 0)) ->
            tuple_spine_shape(tuple)

          union_ctor_atom?(a) and union_tuple_spine_pair?(b) ->
            tuple_spine_shape(tuple)

          true ->
            union_tuple_shape([a | [b]])
        end

      [ctor | args] when is_atom(ctor) ->
        union_tuple_shape([ctor | args])

      elems when length(elems) >= 3 ->
        if Enum.all?(elems, &union_ctor_display_cell?/1) do
          {:union_spine, elems}
        else
          tuple_spine_shape(tuple)
        end

      _elems ->
        tuple_spine_shape(tuple)
    end
  end

  defp wire_shape(atom) when is_atom(atom) do
    if union_ctor_atom?(atom) do
      {:ctor, Atom.to_string(atom), []}
    else
      :plain
    end
  end

  defp wire_shape(list) when is_list(list), do: {:list, list}
  defp wire_shape(map) when is_map(map), do: {:record, Map.to_list(map)}
  defp wire_shape(_), do: :plain

  defp union_ctor_display_cell?({ctor, _}) when is_atom(ctor), do: union_ctor_atom?(ctor)
  defp union_ctor_display_cell?(atom) when is_atom(atom), do: union_ctor_atom?(atom)
  defp union_ctor_display_cell?(_), do: false

  defp union_tuple_shape([ctor | args]) when is_atom(ctor) do
    case ctor do
      :True -> {:ctor, "True", []}
      :False -> {:ctor, "False", []}
      ctor when is_atom(ctor) ->
        case Atom.to_string(ctor) do
          <<first::utf8, _::binary>> when first in ?A..?Z ->
            {:ctor, Atom.to_string(ctor), args}

          _ ->
            tuple_spine_shape(List.to_tuple([ctor | args]))
        end
    end
  end

  defp tuple_spine_shape(tuple) when is_tuple(tuple) do
    case tuple_size(tuple) do
      2 -> {:tuple, elem(tuple, 0), elem(tuple, 1)}
      _ -> tuple |> Tuple.to_list() |> nested_pair_spine()
    end
  end

  defp nested_pair_spine([value]), do: {:tuple, value, nil}
  defp nested_pair_spine([first, second]), do: {:tuple, first, second}
  defp nested_pair_spine([first | rest]), do: {:tuple, first, nested_pair_rest(rest)}

  defp nested_pair_rest([value]), do: value
  defp nested_pair_rest([first | rest]), do: {first, nested_pair_rest(rest)}

  defp format_tuple_spine(first, rest) do
    case flatten_union_display_spine(first, rest) do
      {:ok, cells} ->
        Enum.map_join(cells, ",", &format_value/1)

      :error ->
        case flatten_union_ctor_chain(first, rest) do
          {:ok, atoms} ->
            Enum.map_join(atoms, ",", &format_value/1)

          :error ->
            format_tuple_spine_default(first, rest)
        end
    end
  end

  defp format_tuple_spine_default(first, rest) do
    first_str = format_value(first)

    if rest == nil do
      first_str
    else
      rest_str = format_tuple_spine_loop(rest)
      if rest_str == "", do: first_str, else: first_str <> "," <> rest_str
    end
  end

  defp flatten_union_ctor_chain(first, rest) do
    with {:ok, left} <- flatten_union_ctor_chain_cell(first),
         {:ok, right} <- flatten_union_ctor_chain_cell(rest) do
      {:ok, left ++ right}
    else
      _ -> :error
    end
  end

  defp flatten_union_ctor_chain_cell(atom) when is_atom(atom) do
    if union_ctor_atom?(atom), do: {:ok, [atom]}, else: :error
  end

  defp flatten_union_ctor_chain_cell({left, right})
       when is_tuple({left, right}) and tuple_size({left, right}) == 2 do
    flatten_union_ctor_chain(left, right)
  end

  defp flatten_union_ctor_chain_cell(_), do: :error

  defp flatten_union_display_spine(first, rest) do
    with true <- union_display_cell?(first),
         {:ok, tail} <- flatten_union_display_rest(rest) do
      {:ok, [first | tail]}
    else
      _ -> :error
    end
  end

  defp flatten_union_display_rest({left, right}) when is_tuple({left, right}) and tuple_size({left, right}) == 2 do
    cell = {left, right}

    if union_display_leaf_cell?(cell) do
      {:ok, [cell]}
    else
      with true <- union_display_cell?(left),
           {:ok, tail} <- flatten_union_display_rest(right) do
        {:ok, [left | tail]}
      else
        _ -> if union_display_cell?(right), do: {:ok, [right]}, else: :error
      end
    end
  end

  defp flatten_union_display_rest(cell) do
    if union_display_cell?(cell), do: {:ok, [cell]}, else: :error
  end

  defp union_display_cell?({left, right}) when is_atom(left) and is_atom(right) do
    union_ctor_atom?(left) and union_ctor_atom?(right) and false
  end

  defp union_display_cell?({ctor, _payload}) when is_atom(ctor), do: union_ctor_atom?(ctor)

  defp union_display_cell?(atom) when is_atom(atom), do: union_ctor_atom?(atom)
  defp union_display_cell?(_), do: false

  defp union_display_leaf_cell?({ctor, payload}) when is_atom(ctor) do
    union_ctor_atom?(ctor) and not (is_atom(payload) and union_ctor_atom?(payload)) and
      not elm_tuple_cell?(payload)
  end

  defp union_display_leaf_cell?(_), do: false

  defp format_tuple_spine_loop({mid, rest} = cell) when is_tuple(cell) and tuple_size(cell) == 2 do
    cond do
      union_ctor_tuple?(cell) ->
        format_value(cell)

      union_ctor_tuple?(mid) ->
        format_value(cell)

      union_ctor_atom?(mid) ->
        format_value(cell)

      not elm_tuple_cell?(mid) and elm_tuple_cell?(rest) ->
        mid_str = format_value(mid)
        rest_str = format_value(rest)
        if rest_str == "", do: mid_str, else: mid_str <> "," <> rest_str

      true ->
        mid_str = format_value(mid)
        rest_str = format_value(rest)
        if rest_str == "", do: mid_str, else: mid_str <> "," <> rest_str
    end
  end

  defp format_tuple_spine_loop(rest), do: format_value(rest)

  defp union_ctor_tuple?({ctor, payload}) when is_atom(ctor),
    do: union_ctor_atom?(ctor) and not elm_tuple_cell?(payload)

  defp union_ctor_tuple?(_), do: false

  defp union_tuple_spine_pair?({left, right}) when is_atom(left) and is_atom(right),
    do: union_ctor_atom?(left) and union_ctor_atom?(right)

  defp union_tuple_spine_pair?({left, right}) when is_tuple({left, right}) and tuple_size({left, right}) == 2,
    do: union_ctor_atom?(elem({left, right}, 0)) and union_tuple_spine_pair?(right)

  defp union_tuple_spine_pair?(_), do: false

  defp task_debug_label(:succeed, _payload), do: "<Task:succeed>"
  defp task_debug_label(:fail, _payload), do: "<Task:fail>"
  defp task_debug_label(:and_then, _payload), do: "<Task:andThen>"
  defp task_debug_label(:spawn, _payload), do: "<Task:spawn>"

  defp task_debug_label(:map, {_fun, inner}) do
    case wire_shape(inner) do
      {:task, label} -> label
      _ -> "<Task:map>"
    end
  end

  defp elm_tuple_cell?(term) when is_tuple(term) and tuple_size(term) == 2, do: true
  defp elm_tuple_cell?(_), do: false

  defp union_ctor_atom?(ctor) when is_atom(ctor) do
    case Atom.to_string(ctor) do
      <<first::utf8, _::binary>> -> first in ?A..?Z
      _ -> false
    end
  end

  defp union_ctor_atom?(_), do: false

  defp record_fields_to_string(fields) do
    fields
    |> Enum.sort_by(fn {key, _} -> record_field_sort_key(key) end)
    |> Enum.map_join(", ", fn
      {key, val} when is_atom(key) -> Atom.to_string(key) <> " = " <> format_value(val)
      {key, val} when is_binary(key) -> key <> " = " <> format_value(val)
    end)
  end

  defp record_field_sort_key(key) when is_atom(key), do: Atom.to_string(key)
  defp record_field_sort_key(key) when is_binary(key), do: key

  defp format_manager(%{"$" => 1, "k" => key, "l" => leaf}) do
    "{ $ = 1, k = " <> format_value(key) <> ", l = " <> format_value(leaf) <> " }"
  end

  defp format_manager(%{"$" => 2, "m" => items}) when is_list(items) do
    "{ $ = 2, m = [" <> Enum.map_join(items, ",", &format_value/1) <> "] }"
  end

  defp format_manager(%{"$" => 3, "n" => fun, "o" => inner}) do
    "{ $ = 3, n = " <> format_value(fun) <> ", o = " <> format_value(inner) <> " }"
  end

  defp format_manager(map) when is_map(map) do
    "{ " <>
      (map |> Map.to_list() |> Enum.map_join(", ", fn {k, v} -> "#{k} = #{format_value(v)}" end)) <>
      " }"
  end

  defp format_scientific_float(value) do
    value
    |> then(&:io_lib_format.fwrite("~.6e", [&1]))
    |> IO.iodata_to_binary()
    |> String.downcase()
  end

  defp plain_to_string(value) when is_function(value), do: "<function>"
  defp plain_to_string(:nan), do: "nan"
  defp plain_to_string(:infinity), do: "Infinity"
  defp plain_to_string(:negative_infinity), do: "Negative Infinity"
  defp plain_to_string(true), do: "True"
  defp plain_to_string(false), do: "False"
  defp plain_to_string(nil), do: "()"

  defp plain_to_string(value) when is_binary(value), do: "\"" <> escape_elm_string(value) <> "\""
  defp plain_to_string(value) when is_integer(value), do: Integer.to_string(value)

  defp plain_to_string(value) when is_float(value) and value != value, do: "NaN"

  defp plain_to_string(value) when is_float(value) do
    cond do
      value == 0.0 -> "0"
      abs(value) < 1.0e-4 -> format_scientific_float(value)
      trunc(value) == value -> Integer.to_string(trunc(value))
      true -> :erlang.float_to_binary(value, [:compact, decimals: 6])
    end
  end

  defp plain_to_string(value), do: inspect(value, limit: :infinity, printable_limit: :infinity)

  defp format_char_payload({:elmx_char, code}) when is_integer(code), do: format_char_literal(code)
  defp format_char_payload(code) when is_integer(code), do: format_char_literal(code)

  defp format_char_payload(value) when is_binary(value) do
    case char_codepoint(value) do
      {:ok, code} -> format_char_literal(code)
      :error -> format_value(value)
    end
  end

  defp format_char_payload(value), do: format_value(value)

  defp format_char_literal(code) when is_integer(code) do
    cond do
      code == 0 -> "'\\0'"
      code == ?\\ -> "'\\\\'"
      code == ?' -> "'\\''"
      code == ?\n -> "'\\n'"
      code == ?\r -> "'\\r'"
      code == ?\t -> "'\\t'"
      true ->
        case <<code::utf8>> do
          <<c::utf8>> -> "'" <> <<c::utf8>> <> "'"
          _ -> Integer.to_string(code)
        end
    end
  end

  defp char_codepoint(bin) when is_binary(bin) do
    case String.next_codepoint(bin) do
      {<<cp::utf8>>, ""} -> {:ok, cp}
      _ -> :error
    end
  end

  defp escape_elm_string(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\t", "\\t")
    |> String.replace("\r", "\\r")
    |> String.replace("\v", "\\v")
    |> String.replace("\0", "\\0")
  end
end
