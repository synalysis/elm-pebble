defmodule Elmx.Backend.ElixirCodegen.Emit.Patterns.Match.Pattern do
  @moduledoc false

  alias Elmx.Backend.ElixirCodegen.Emit.Helpers
  alias Elmx.Types

  @type env :: Types.emit_env()

  @spec branch_pattern(map(), env()) :: String.t()
  def branch_pattern(branch, env \\ %{})

  def branch_pattern(%{pattern: %{kind: :wildcard}}, _env), do: "_"

  def branch_pattern(%{pattern: %{kind: :var, name: name}}, %{maybe_unwrap_just: true} = env)
       when is_binary(name) and name not in ["_", ""] do
    "{:Just, #{Helpers.binding_ref(name, env)}}"
  end

  def branch_pattern(%{pattern: %{kind: :var, name: name}}, env) when is_binary(name),
    do: Helpers.pattern_var_name(name, env)

  def branch_pattern(%{pattern: %{kind: :string, value: value}}, _env) when is_binary(value),
    do: inspect(value)

  def branch_pattern(%{pattern: %{kind: :char, value: value}}, _env) when is_integer(value),
    do: "{:elmx_char, #{value}}"

  def branch_pattern(%{pattern: %{kind: :int, value: value}}, _env) when is_integer(value),
    do: Integer.to_string(value)

  def branch_pattern(%{pattern: %{kind: :bool, value: value}}, _env) when is_boolean(value),
    do: if(value, do: "true", else: "false")

  def branch_pattern(%{pattern: %{op: :bool_literal, value: value}}, _env) when is_boolean(value),
    do: if(value, do: "true", else: "false")

  def branch_pattern(%{pattern: %{kind: :list, elements: []}}, _env), do: "[]"

  def branch_pattern(%{pattern: %{kind: :list, elements: elements}}, env) when is_list(elements) do
    inner = Enum.map_join(elements, ", ", &pattern_arg(&1, env))
    "[#{inner}]"
  end

  def branch_pattern(%{pattern: %{kind: :cons, head: head, tail: tail}}, env) do
    "[#{pattern_arg(head, env)} | #{list_tail_pattern(tail, env)}]"
  end

  def branch_pattern(%{pattern: %{kind: :tuple, elements: elements}}, env) when is_list(elements) do
    "{" <> Enum.map_join(elements, ", ", &tuple_case_elem(&1, env)) <> "}"
  end

  def branch_pattern(%{pattern: %{kind: :constructor, name: "[]"}}, _env), do: "[]"

  def branch_pattern(%{pattern: %{kind: :constructor, name: "::", arg_pattern: arg} = pat}, env) do
    inner = cons_list_case_pattern(arg, env)

    case Map.get(pat, :bind) do
      bind when is_binary(bind) and bind != "" ->
        "#{inner} = #{Helpers.pattern_var_name(bind, env)}"

      _ ->
        inner
    end
  end

  def branch_pattern(%{pattern: %{kind: :constructor, name: name} = pat}, env) do
    ctor = pattern_ctor_name(name)

    case Map.get(pat, :arg_pattern) do
      %{kind: :wildcard} ->
        bool_case_pattern(ctor, "{:#{ctor}, _}")

      nil ->
        case Map.get(pat, :bind) do
          bind when is_binary(bind) and bind != "" ->
            bool_case_pattern(ctor, "{:#{ctor}, #{Helpers.pattern_var_name(bind, env)}}")

          _ ->
            bool_case_pattern(ctor, ":#{ctor}")
        end

      other ->
        bool_case_pattern(ctor, constructor_case_pattern(ctor, other, env))
    end
  end

  def branch_pattern(%{pattern: %{op: :var, name: name}}, env) when is_binary(name),
    do: Helpers.pattern_var_name(name, env)

  def branch_pattern(%{pattern: %{kind: :record, bind: bind, fields: fields}}, env)
       when is_list(fields) do
    record_case_pattern(bind, fields, env)
  end

  def branch_pattern(%{pattern: %{kind: :record, fields: fields}}, env) when is_list(fields) do
    record_case_pattern(nil, fields, env)
  end

  def branch_pattern(%{pattern: %{op: :record, fields: fields}}, env) when is_list(fields) do
    record_case_pattern(nil, fields, env)
  end

  def branch_pattern(%{pattern: %{op: :alias, bind: bind, pattern: inner}}, env) do
    inner_pat = branch_pattern(%{pattern: inner}, env)

    if is_binary(bind) and bind != "" do
      "#{inner_pat} = #{Helpers.pattern_var_name(bind, env)}"
    else
      inner_pat
    end
  end

  def branch_pattern(%{pattern: %{op: :alias, pattern: inner}}, env),
    do: branch_pattern(%{pattern: inner}, env)

  def branch_pattern(%{pattern: %{op: :constructor_call, name: "::", args: args}}, env) do
    cons_list_case_pattern(%{kind: :tuple, elements: args}, env)
  end

  def branch_pattern(%{pattern: %{op: :constructor_call, name: name, args: args}}, _env) do
    case args do
      [] ->
        name

      list ->
        bindings = Enum.map_join(list, ", ", fn _ -> "_" end)
        "{:#{pattern_ctor_name(name)}, #{bindings}}"
    end
  end

  def branch_pattern(%{pattern: _pattern}, _env), do: "_"
  def branch_pattern(_, _env), do: "_"

  @spec pattern_ctor_name(String.t()) :: String.t()
  def pattern_ctor_name(name) when is_binary(name) do
    name |> String.split(".") |> List.last()
  end

  @spec record_pattern_key(String.t() | atom()) :: String.t()
  def record_pattern_key(name) when is_binary(name) or is_atom(name), do: inspect(name)

  @spec record_case_pattern(String.t() | nil, list(), env()) :: String.t()
  def record_case_pattern(bind, fields, env \\ %{}) when is_list(fields) do
    field_pattern = fn name ->
      "#{record_pattern_key(name)} => #{Helpers.pattern_var_name(to_string(name), env)}"
    end

    parts =
      Enum.map(fields, fn
        name when is_binary(name) -> field_pattern.(name)
        name when is_atom(name) -> field_pattern.(name)
        %{name: name} -> field_pattern.(name)
        {name, _} when is_binary(name) or is_atom(name) -> field_pattern.(name)
      end)

    map_pat = "%{#{Enum.join(parts, ", ")}}"

    if is_binary(bind) and bind != "" do
      "#{map_pat} = #{Helpers.pattern_var_name(bind, env)}"
    else
      map_pat
    end
  end

  @spec bool_case_pattern(String.t(), String.t()) :: String.t()
  def bool_case_pattern("True", _default), do: "true"
  def bool_case_pattern("False", _default), do: "false"
  def bool_case_pattern(_ctor, default), do: default

  @spec cons_list_case_pattern(map(), env()) :: String.t()
  def cons_list_case_pattern(%{kind: :tuple, elements: [head, tail]}, env) do
    {heads, final_tail} = flatten_cons_pattern(head, tail, env)
    "[#{Enum.join(heads, ", ")} | #{final_tail}]"
  end

  def cons_list_case_pattern(_, _env), do: "_"

  defp flatten_cons_pattern(head, tail, env) do
    {rest_heads, final_tail} = flatten_cons_tail(tail, env)
    {[pattern_arg(head, env) | rest_heads], final_tail}
  end

  defp flatten_cons_tail(
         %{kind: :constructor, name: "::", arg_pattern: %{kind: :tuple, elements: [head, tail]}},
         env
       ) do
    {rest_heads, final_tail} = flatten_cons_tail(tail, env)
    {[pattern_arg(head, env) | rest_heads], final_tail}
  end

  defp flatten_cons_tail(%{kind: :constructor, name: "[]"}, _env), do: {[], "[]"}

  defp flatten_cons_tail(other, env), do: {[], list_tail_pattern(other, env)}

  @spec tuple_case_elem(map(), env()) :: String.t()
  def tuple_case_elem(%{kind: :constructor, name: name, bind: bind, arg_pattern: nil}, env)
       when is_binary(bind) and bind != "" do
    "{:#{pattern_ctor_name(name)}, #{Helpers.pattern_var_name(bind, env)}}"
  end

  def tuple_case_elem(%{kind: :constructor, name: name, arg_pattern: ap}, env) when is_map(ap) do
    ctor = pattern_ctor_name(name)
    constructor_case_pattern(ctor, ap, env)
  end

  def tuple_case_elem(%{kind: :var, name: name}, env) when is_binary(name),
    do: Helpers.pattern_var_name(name, env)

  def tuple_case_elem(other, env), do: pattern_arg(other, env)

  @spec pattern_arg(map(), env()) :: String.t()
  def pattern_arg(pattern, env \\ %{})

  def pattern_arg(%{kind: :wildcard}, _env), do: "_"

  def pattern_arg(%{kind: :var, name: name}, env) when is_binary(name),
    do: Helpers.pattern_var_name(name, env)

  def pattern_arg(%{kind: :string, value: value}, _env) when is_binary(value), do: inspect(value)

  def pattern_arg(%{kind: :char, value: value}, _env) when is_integer(value),
    do: "{:elmx_char, #{value}}"

  def pattern_arg(%{kind: :int, value: value}, _env) when is_integer(value), do: Integer.to_string(value)

  def pattern_arg(%{kind: :bool, value: value}, _env) when is_boolean(value),
    do: if(value, do: "true", else: "false")

  def pattern_arg(%{op: :bool_literal, value: value}, _env) when is_boolean(value),
    do: if(value, do: "true", else: "false")

  def pattern_arg(%{kind: :list, elements: []}, _env), do: "[]"

  def pattern_arg(%{kind: :record, bind: bind, fields: fields}, env) when is_list(fields) do
    record_case_pattern(bind, fields, env)
  end

  def pattern_arg(%{kind: :record, fields: fields}, env) when is_list(fields) do
    record_case_pattern(nil, fields, env)
  end

  def pattern_arg(%{kind: :cons, head: head, tail: tail}, env),
    do: "[#{pattern_arg(head, env)} | #{list_tail_pattern(tail, env)}]"

  def pattern_arg(%{kind: :tuple, elements: elements}, env) when is_list(elements) do
    "{" <> Enum.map_join(elements, ", ", &pattern_arg(&1, env)) <> "}"
  end

  def pattern_arg(%{kind: :constructor, name: "()", arg_pattern: nil}, _env), do: "nil"
  def pattern_arg(%{kind: :constructor, name: "()", arg_pattern: other}, env), do: pattern_arg(other, env)

  def pattern_arg(%{kind: :constructor, name: name} = pat, env) do
    ctor = pattern_ctor_name(name)

    case Map.get(pat, :arg_pattern) do
      %{kind: :wildcard} ->
        "{:#{ctor}, _}"

      nil ->
        case Map.get(pat, :bind) do
          bind when is_binary(bind) and bind != "" ->
            bool_case_pattern(ctor, "{:#{ctor}, #{Helpers.pattern_var_name(bind, env)}}")

          _ ->
            bool_case_pattern(ctor, ":#{ctor}")
        end

      other ->
        constructor_case_pattern(ctor, other, env)
    end
  end

  def pattern_arg(_, _env), do: "_"

  @spec constructor_case_pattern(String.t(), map(), env()) :: String.t()
  def constructor_case_pattern(ctor, %{kind: :constructor, name: "()"}, _env), do: "{:#{ctor}, nil}"

  def constructor_case_pattern(ctor, %{kind: :record} = record, env) do
    "{:#{ctor}, #{pattern_arg(record, env)}}"
  end

  def constructor_case_pattern(ctor, %{kind: :tuple, elements: elements}, env) when is_list(elements) do
    bindings =
      cond do
        length(elements) == 1 ->
          pattern_arg(hd(elements), env)

        single_tuple_payload_ctor?(ctor) ->
          "{" <> Enum.map_join(elements, ", ", &pattern_arg(&1, env)) <> "}"

        plain_product_tuple_elements?(elements) ->
          "{" <> Enum.map_join(elements, ", ", &pattern_arg(&1, env)) <> "}"

        true ->
          elements
          |> flatten_ctor_payload_pattern_elements(env)
          |> Enum.map_join(", ", &pattern_arg(&1, env))
      end

    "{:#{ctor}, #{bindings}}"
  end

  def constructor_case_pattern(ctor, other, env), do: "{:#{ctor}, #{pattern_arg(other, env)}}"

  defp single_tuple_payload_ctor?(ctor) when ctor in ["Ok", "Err", "Just"], do: true
  defp single_tuple_payload_ctor?(_), do: false

  @spec plain_product_tuple_elements?([map()]) :: boolean()
  def plain_product_tuple_elements?(elements) when is_list(elements) do
    length(elements) > 1 and
      Enum.any?(elements, &match?(%{kind: :string}, &1)) and
      Enum.all?(elements, fn
        %{kind: kind} when kind in [:string, :int, :var, :wildcard] -> true
        _ -> false
      end)
  end

  @spec flatten_ctor_payload_pattern_elements([map()], env()) :: [map()]
  def flatten_ctor_payload_pattern_elements(elements, _env) when is_list(elements) do
    Enum.flat_map(elements, fn
      %{kind: :tuple, elements: nested} when is_list(nested) ->
        flatten_ctor_payload_pattern_elements(nested, %{})

      other ->
        [other]
    end)
  end

  @spec list_tail_pattern(map(), env()) :: String.t()
  def list_tail_pattern(%{kind: :list, elements: []}, _env), do: "[]"

  def list_tail_pattern(%{kind: :var, name: name}, env) when is_binary(name),
    do: Helpers.pattern_var_name(name, env)

  def list_tail_pattern(%{kind: :wildcard}, _env), do: "_"
  def list_tail_pattern(_, _env), do: "_"
end
