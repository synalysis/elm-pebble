defmodule Elmx.Backend.ElixirCodegen.Emit.Patterns.Match.Bindings do
  @moduledoc false

  alias Elmx.Types

  @type env :: Types.emit_env()

  @spec branch_env(map(), env()) :: env()
  def branch_env(branch, env) do
    branch
    |> branch_pattern_root()
    |> pattern_binding_names()
    |> Enum.reduce(env, fn name, acc -> Map.put(acc, String.to_atom(name), true) end)
  end

  @spec branch_pattern_root(map()) :: map()
  def branch_pattern_root(%{pattern: pattern}), do: pattern
  def branch_pattern_root(pattern), do: pattern

  @spec pattern_binding_names(map()) :: [String.t()]
  def pattern_binding_names(%{kind: :var, name: name}) when is_binary(name), do: [name]

  def pattern_binding_names(%{kind: :constructor, bind: bind, arg_pattern: pattern})
      when is_binary(bind) and bind != "" and is_map(pattern) do
    [bind | pattern_binding_names(pattern)]
  end

  def pattern_binding_names(%{kind: :constructor, bind: bind})
      when is_binary(bind) and bind != "" do
    [bind]
  end

  def pattern_binding_names(%{kind: :constructor, arg_pattern: pattern}) when is_map(pattern) do
    pattern_binding_names(pattern)
  end

  def pattern_binding_names(%{kind: :cons, head: head, tail: tail}) do
    pattern_binding_names(head) ++ pattern_binding_names(tail)
  end

  def pattern_binding_names(%{kind: :tuple, elements: elements}) when is_list(elements) do
    Enum.flat_map(elements, &pattern_binding_names/1)
  end

  def pattern_binding_names(%{kind: :list, elements: elements}) when is_list(elements) do
    Enum.flat_map(elements, &pattern_binding_names/1)
  end

  def pattern_binding_names(%{kind: :record, bind: bind, fields: fields})
       when is_list(fields) do
    field_names =
      Enum.map(fields, fn
        name when is_binary(name) -> name
        name when is_atom(name) -> Atom.to_string(name)
        %{name: name} -> to_string(name)
        {name, _} when is_binary(name) or is_atom(name) -> to_string(name)
      end)

    Enum.reject([bind | field_names], &(&1 in [nil, ""]))
  end

  def pattern_binding_names(%{kind: :alias, pattern: inner, bind: bind})
       when is_binary(bind) and bind != "" do
    [bind | pattern_binding_names(inner)]
  end

  def pattern_binding_names(%{kind: :alias, pattern: inner}), do: pattern_binding_names(inner)
  def pattern_binding_names(_), do: []
end
