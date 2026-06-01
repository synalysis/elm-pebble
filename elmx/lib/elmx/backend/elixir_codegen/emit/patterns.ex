defmodule Elmx.Backend.ElixirCodegen.Emit.Patterns do
  @moduledoc false

  alias Elmx.Types

  @type env :: Types.emit_env()
  @type compile_result :: {iodata(), env(), non_neg_integer()}

  def compile_case(%{subject: subject, branches: branches}, env, counter) when is_binary(subject) do
    subj =
      if Elmx.Backend.ElixirCodegen.Emit.Helpers.parameter_binding?(subject, env) do
        Elmx.Backend.ElixirCodegen.Emit.Helpers.binding_ref(subject, env)
      else
        Elmx.Backend.ElixirCodegen.Emit.Helpers.var_ref(subject, env)
      end

    clauses =
      branches
      |> order_case_branches()
      |> Enum.map(fn branch ->
        pattern = branch_pattern(branch, env)
        {body, _, _} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(branch.expr, branch_env(branch, env), 0)
        "  #{pattern} ->\n    #{IO.iodata_to_binary(body)}"
      end)

    {["case ", subj, " do\n", Enum.join(clauses, "\n"), "\nend"], env, counter}
  end

  def compile_case(%{subject: subject, branches: branches}, env, counter) do
    {subj, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(subject, env, counter)

    clauses =
      branches
      |> order_case_branches()
      |> Enum.map(fn branch ->
        pattern = branch_pattern(branch, env)
        {body, _, _} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(branch.expr, branch_env(branch, env), 0)
        "  #{pattern} ->\n    #{IO.iodata_to_binary(body)}"
      end)

    {["case ", subj, " do\n", Enum.join(clauses, "\n"), "\nend"], env, c1}
  end

  def branch_env(branch, env) do
    branch
    |> branch_pattern_root()
    |> pattern_binding_names()
    |> Enum.reduce(env, fn name, acc -> Map.put(acc, String.to_atom(name), true) end)
  end

  # Wildcard branches must be last in Elixir `case` (IR order is not guaranteed).
  def order_case_branches(branches) when is_list(branches) do
    branches
    |> Enum.sort_by(&case_branch_sort_key/1)
  end

  def case_branch_sort_key(branch) do
    cond do
      wildcard_case_branch?(branch) -> {2, 0}
      constructor_wildcard_arg_branch?(branch) -> {1, 0}
      true -> {0, 0}
    end
  end

  def wildcard_case_branch?(branch) do
    case branch_pattern_root(branch) do
      %{kind: :wildcard} -> true
      %{kind: :var, name: name} when name in ["_", ""] -> true
      _ -> false
    end
  end

  def constructor_wildcard_arg_branch?(branch) do
    case branch_pattern_root(branch) do
      %{kind: :constructor, arg_pattern: %{kind: :wildcard}} -> true
      _ -> false
    end
  end

  def branch_pattern_root(%{pattern: pattern}), do: pattern
  def branch_pattern_root(pattern), do: pattern

  def pattern_binding_names(%{bind: bind}) when is_binary(bind) and bind != "", do: [bind]

  def pattern_binding_names(%{kind: :var, name: name}) when is_binary(name), do: [name]

  def pattern_binding_names(%{kind: :cons, head: head, tail: tail}) do
    pattern_binding_names(head) ++ pattern_binding_names(tail)
  end

  def pattern_binding_names(%{kind: :tuple, elements: elements}) when is_list(elements) do
    Enum.flat_map(elements, &pattern_binding_names/1)
  end

  def pattern_binding_names(%{kind: :list, elements: elements}) when is_list(elements) do
    Enum.flat_map(elements, &pattern_binding_names/1)
  end

  def pattern_binding_names(%{kind: :constructor, arg_pattern: pattern}) when is_map(pattern) do
    pattern_binding_names(pattern)
  end

  def pattern_binding_names(%{kind: :alias, pattern: inner, bind: bind})
       when is_binary(bind) and bind != "" do
    [bind | pattern_binding_names(inner)]
  end

  def pattern_binding_names(%{kind: :alias, pattern: inner}), do: pattern_binding_names(inner)
  def pattern_binding_names(_), do: []

  def branch_pattern(branch, env \\ %{})

  def branch_pattern(%{pattern: %{kind: :wildcard}}, _env), do: "_"

  def branch_pattern(%{pattern: %{kind: :var, name: name}}, _env) when is_binary(name),
    do: Elmx.Backend.ElixirCodegen.Emit.Helpers.binding_ref(name, %{})

  def branch_pattern(%{pattern: %{kind: :string, value: value}}, _env) when is_binary(value),
    do: inspect(value)

  def branch_pattern(%{pattern: %{kind: :int, value: value}}, _env) when is_integer(value),
    do: Integer.to_string(value)

  def branch_pattern(%{pattern: %{kind: :list, elements: []}}, _env), do: "[]"

  def branch_pattern(%{pattern: %{kind: :list, elements: elements}}, env) when is_list(elements) do
    inner = Enum.map_join(elements, ", ", &pattern_arg(&1, env))
    "[#{inner}]"
  end

  def branch_pattern(%{pattern: %{kind: :cons, head: head, tail: tail}}, env) do
    "[#{pattern_arg(head, env)} | #{list_tail_pattern(tail)}]"
  end

  def branch_pattern(%{pattern: %{kind: :tuple, elements: elements}}, _env) when is_list(elements) do
    "{" <> Enum.map_join(elements, ", ", &tuple_case_elem/1) <> "}"
  end

  def branch_pattern(%{pattern: %{kind: :constructor, name: "[]"}}, _env), do: "[]"

  def branch_pattern(%{pattern: %{kind: :constructor, name: "::", arg_pattern: arg}}, _env) do
    cons_list_case_pattern(arg)
  end

  def branch_pattern(%{pattern: %{kind: :constructor, name: name} = pat}, env) do
    ctor = pattern_ctor_name(name)

    case Map.get(pat, :arg_pattern) do
      %{kind: :wildcard} ->
        bool_case_pattern(ctor, "{:#{ctor}, _}")

      nil ->
        case Map.get(pat, :bind) do
          bind when is_binary(bind) and bind != "" ->
            bool_case_pattern(ctor, "{:#{ctor}, #{bind}}")

          _ ->
            bool_case_pattern(ctor, ":#{ctor}")
        end

      other ->
        bool_case_pattern(ctor, constructor_case_pattern(ctor, other, env))
    end
  end

  def branch_pattern(%{pattern: %{op: :var, name: name}}, _env), do: Elmx.Backend.ElixirCodegen.Emit.Helpers.binding_ref(name, %{})
  def branch_pattern(%{pattern: %{op: :alias, pattern: inner}}, env), do: branch_pattern(%{pattern: inner}, env)

  def branch_pattern(%{pattern: %{op: :record, fields: fields}}, _env) when is_list(fields) do
    parts =
      Enum.map(fields, fn
        %{name: name} -> "#{record_pattern_key(name)}: _"
        {name, _} -> "#{record_pattern_key(name)}: _"
        name when is_binary(name) or is_atom(name) -> "#{record_pattern_key(name)}: _"
      end)

    "%{#{Enum.join(parts, ", ")}}"
  end

  def branch_pattern(%{pattern: %{op: :constructor_call, name: "::", args: args}}, _env) do
    cons_list_case_pattern(%{kind: :tuple, elements: args})
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

  def pattern_ctor_name(name) when is_binary(name) do
    name |> String.split(".") |> List.last()
  end

  def record_pattern_key(name) when is_binary(name) or is_atom(name), do: inspect(name)

  def bool_case_pattern("True", _default), do: "true"
  def bool_case_pattern("False", _default), do: "false"
  def bool_case_pattern(_ctor, default), do: default

  def cons_list_case_pattern(%{kind: :tuple, elements: [head, tail]}) do
    "[#{pattern_arg(head)} | #{cons_pattern_tail(tail)}]"
  end

  def cons_list_case_pattern(_), do: "_"

  def cons_pattern_tail(%{kind: :constructor, name: "::", arg_pattern: arg}),
    do: cons_list_case_pattern(arg)

  def cons_pattern_tail(%{kind: :constructor, name: "[]"}), do: "[]"
  def cons_pattern_tail(other), do: list_tail_pattern(other)

  def tuple_case_elem(%{kind: :constructor, name: name, bind: bind, arg_pattern: nil})
       when is_binary(bind) and bind != "" do
    "{:#{pattern_ctor_name(name)}, #{bind}}"
  end

  def tuple_case_elem(%{kind: :constructor, name: name, arg_pattern: ap}) when is_map(ap) do
    "{:#{pattern_ctor_name(name)}, #{pattern_arg(ap, %{})}}"
  end

  def tuple_case_elem(%{kind: :var, name: name}) when is_binary(name), do: name
  def tuple_case_elem(other), do: pattern_arg(other, %{})

  def pattern_arg(pattern, env \\ %{})

  def pattern_arg(%{kind: :wildcard}, _env), do: "_"
  def pattern_arg(%{kind: :var, name: name}, env) when is_binary(name) do
    if Map.get(env, String.to_atom(name)) == true do
      Elmx.Backend.ElixirCodegen.Emit.Helpers.param_var_name(name, env)
    else
      name
    end
  end

  def pattern_arg(%{kind: :string, value: value}, _env) when is_binary(value), do: inspect(value)
  def pattern_arg(%{kind: :int, value: value}, _env) when is_integer(value), do: Integer.to_string(value)

  def pattern_arg(%{kind: :list, elements: []}, _env), do: "[]"

  def pattern_arg(%{kind: :cons, head: head, tail: tail}, env),
    do: "[#{pattern_arg(head, env)} | #{list_tail_pattern(tail)}]"

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
          bind when is_binary(bind) and bind != "" -> "{:#{ctor}, #{bind}}"
          _ -> ":#{ctor}"
        end

      other ->
        constructor_case_pattern(ctor, other, env)
    end
  end

  def pattern_arg(_, _env), do: "_"

  def constructor_case_pattern(ctor, %{kind: :constructor, name: "()"}, _env), do: "{:#{ctor}, nil}"

  def constructor_case_pattern(ctor, %{kind: :tuple, elements: elements}, env) when is_list(elements) do
    bindings =
      if plain_product_tuple_elements?(elements) do
        "{" <> Enum.map_join(elements, ", ", &pattern_arg(&1, env)) <> "}"
      else
        elements
        |> flatten_ctor_payload_pattern_elements(env)
        |> Enum.map_join(", ", &pattern_arg(&1, env))
      end

    "{:#{ctor}, #{bindings}}"
  end

  def constructor_case_pattern(ctor, other, env), do: "{:#{ctor}, #{pattern_arg(other, env)}}"

  # `Ok ("units", value)` is a single pair payload (string key + var), not a flat multi-arg ctor.
  def plain_product_tuple_elements?(elements) when is_list(elements) do
    length(elements) > 1 and
      Enum.any?(elements, &match?(%{kind: :string}, &1)) and
      Enum.all?(elements, fn
        %{kind: kind} when kind in [:string, :int, :var, :wildcard] -> true
        _ -> false
      end)
  end

  # Elm lowers n-ary constructor payloads to nested pairs; emit uses flat tagged tuples.
  def flatten_ctor_payload_pattern_elements(elements, _env) when is_list(elements) do
    Enum.flat_map(elements, fn
      %{kind: :tuple, elements: nested} when is_list(nested) ->
        flatten_ctor_payload_pattern_elements(nested, %{})

      other ->
        [other]
    end)
  end

  def list_tail_pattern(%{kind: :list, elements: []}), do: "[]"
  def list_tail_pattern(%{kind: :var, name: name}) when is_binary(name), do: name
  def list_tail_pattern(%{kind: :wildcard}), do: "_"
  def list_tail_pattern(_), do: "_"

end
