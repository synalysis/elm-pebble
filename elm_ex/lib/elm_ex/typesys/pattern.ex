defmodule ElmEx.Typesys.Pattern do
  @moduledoc """
  Elm-style pattern exhaustiveness and redundancy (Nitpick.PatternMatches rules).
  """

  alias ElmEx.Frontend.Module, as: FrontendModule
  alias ElmEx.IR.Lowerer
  alias ElmEx.Typesys.{Diagnostic, Env}

  @spec nitpick([FrontendModule.t()], Env.t()) :: {[FrontendModule.t()], [map()]}
  def nitpick(modules, env) when is_list(modules) do
    {modules, diags} =
      Enum.map_reduce(modules, [], fn mod, acc ->
        {mod, diags} = nitpick_module(mod, env)
        {mod, acc ++ diags}
      end)

    {modules, diags}
  end

  @doc """
  Recover `as`, `::`, nested constructors, and tuples from parser `:unknown` source.
  """
  @spec recover(String.t()) :: {:ok, map()} | :error
  def recover(source) when is_binary(source) do
    source = source |> String.trim() |> unwrap_grouping_parens()

    case parse_pattern(source) do
      {:ok, pat, rest} ->
        if String.trim(rest) == "" do
          {:ok, pat}
        else
          :error
        end

      :error ->
        :error
    end
  end

  def recover(_), do: :error

  defp nitpick_module(%FrontendModule{} = mod, env) do
    exports = Lowerer.project_module_exports(Map.values(env.modules))
    {alias_map, _members, unqualified, _wild, _types} = Lowerer.import_resolution_for(mod, exports)

    env =
      env
      |> Env.put_import_lookup(%{
        alias_map: alias_map,
        import_unqualified_map: unqualified,
        current_module: mod.name
      })
      |> Env.merge_exposed_imports(mod)

    {decls, diags} =
      Enum.map_reduce(mod.declarations, [], fn
        %{kind: :function_definition, expr: expr} = decl, acc ->
          {expr, diags} = walk(expr, env, loc(mod, decl))
          {%{decl | expr: expr}, acc ++ diags}

        decl, acc ->
          {decl, acc}
      end)

    {%{mod | declarations: decls}, diags}
  end

  defp walk(%{op: :case, branches: branches} = expr, env, loc) do
    {branches, nested} =
      Enum.map_reduce(branches || [], [], fn branch, acc ->
        {body, diags} = walk(Map.get(branch, :expr), env, loc)
        {%{branch | expr: body}, acc ++ diags}
      end)

    subject = Map.get(expr, :subject)
    {subject, subj_diags} = walk(subject, env, loc)

    {exhaustive?, diags} = check_case(branches, env, loc)

    branches =
      Enum.map(branches, fn branch ->
        Map.put(branch, :elm_exhaustive?, exhaustive?)
      end)

    expr =
      expr
      |> Map.put(:subject, subject)
      |> Map.put(:branches, branches)
      |> Map.put(:elm_exhaustive?, exhaustive?)

    {expr, nested ++ subj_diags ++ diags}
  end

  defp walk(expr, env, loc) when is_map(expr) do
    {expr, diags} =
      Enum.reduce(expr, {expr, []}, fn
        {k, v}, {acc, diags} when is_map(v) ->
          {v, more} = walk(v, env, loc)
          {Map.put(acc, k, v), diags ++ more}

        {k, vs}, {acc, diags} when is_list(vs) ->
          {vs, more} =
            Enum.map_reduce(vs, [], fn
              item, acc when is_map(item) ->
                {item, d} = walk(item, env, loc)
                {item, acc ++ d}

              item, acc ->
                {item, acc}
            end)

          {Map.put(acc, k, vs), diags ++ more}

        _, acc ->
          acc
      end)

    {expr, diags}
  end

  defp walk(other, _env, _loc), do: {other, []}

  defp check_case(branches, env, loc) do
    patterns =
      branches
      |> Enum.map(&Map.get(&1, :pattern))
      |> Enum.map(&normalize_unknown/1)

    {redundant, missing} = analyze(patterns, env)

    diags =
      Enum.map(redundant, fn idx ->
        Diagnostic.error(
          "unreachable_pattern",
          "This pattern is unreachable.",
          Keyword.put(loc, :name, "branch #{idx}")
        )
      end) ++
        if missing == [] do
          []
        else
          [
            Diagnostic.error(
              "missing_patterns",
              "This `case` does not cover: #{Enum.join(missing, ", ")}",
              loc
            )
          ]
        end

    {missing == [], diags}
  end

  @spec analyze([map() | nil], Env.t()) :: {[integer()], [String.t()]}
  def analyze(patterns, env) do
    patterns = Enum.with_index(patterns)

    {leftover, redundant} =
      Enum.reduce(patterns, {[:anything], []}, fn {pattern, idx}, {leftover, redundant} ->
        new_leftover = leftover_after(leftover, pattern, env)

        if new_leftover == leftover do
          {leftover, [idx | redundant]}
        else
          {new_leftover, redundant}
        end
      end)

    missing = Enum.map(leftover, &format_sketch/1)
    {Enum.reverse(redundant), missing}
  end

  defp normalize_unknown(%{kind: :unknown, source: source} = pat) do
    case recover(source) do
      {:ok, recovered} -> recovered
      :error -> pat
    end
  end

  defp normalize_unknown(pat), do: pat

  defp leftover_after(sketches, pattern, env) do
    sketches
    |> Enum.flat_map(&subtract_one(&1, pattern, env))
    |> Enum.uniq()
  end

  defp subtract_one(sketch, pattern, env) do
    do_subtract(sketch, norm(pattern, env), env)
  end

  defp do_subtract(_sketch, :wild, _env), do: []

  defp do_subtract(sketch, {:as, inner}, env), do: do_subtract(sketch, inner, env)

  defp do_subtract(:anything, {:ctor, name, args}, env) do
    ctor_anything_minus(name, args, env)
  end

  defp do_subtract(:anything, {:tuple, args}, env) do
    do_subtract({:tuple, List.duplicate(:anything, length(args))}, {:tuple, args}, env)
  end

  defp do_subtract(:anything, :nil, _env), do: [{:cons, :anything, :anything}]

  defp do_subtract(:anything, {:cons, h, t}, env) do
    [:nil | do_subtract({:cons, :anything, :anything}, {:cons, h, t}, env)]
  end

  defp do_subtract(:anything, {:list, []}, _env), do: [{:cons, :anything, :anything}]

  defp do_subtract(:anything, {:list, elems}, env) do
    do_subtract(:anything, list_as_cons(elems), env)
  end

  defp do_subtract(:anything, {:lit, kind, value}, _env) do
    [{:except_lits, [{kind, value}]}]
  end

  defp do_subtract(:anything, :unknown, _env), do: [:anything]

  defp do_subtract({:ctor, a, payloads}, {:ctor, b, args}, env) do
    if short(a) == short(b) do
      leftover_product(payloads, args, env)
      |> Enum.map(&{:ctor, a, &1})
    else
      [{:ctor, a, payloads}]
    end
  end

  defp do_subtract({:tuple, payloads}, {:tuple, args}, env) when length(payloads) == length(args) do
    leftover_product(payloads, args, env)
    |> Enum.map(&{:tuple, &1})
  end

  defp do_subtract(:nil, :nil, _env), do: []
  defp do_subtract(:nil, {:list, []}, _env), do: []
  defp do_subtract(:nil, {:cons, _, _}, _env), do: [:nil]
  defp do_subtract(:nil, {:list, [_ | _]}, _env), do: [:nil]

  defp do_subtract({:cons, a, b}, {:cons, h, t}, env) do
    leftover_product([a, b], [h, t], env)
    |> Enum.map(fn [h2, t2] -> {:cons, h2, t2} end)
  end

  defp do_subtract({:cons, a, b}, {:list, elems}, env) do
    do_subtract({:cons, a, b}, list_as_cons(elems), env)
  end

  defp do_subtract({:cons, a, b}, :nil, _env), do: [{:cons, a, b}]

  defp do_subtract({:except_lits, lits}, {:lit, kind, value}, _env) do
    key = {kind, value}

    if key in lits do
      [{:except_lits, lits}]
    else
      [{:except_lits, [key | lits]}]
    end
  end

  defp do_subtract({:except_lits, lits}, _other, _env), do: [{:except_lits, lits}]

  defp do_subtract(sketch, _pattern, _env), do: [sketch]

  defp ctor_anything_minus(name, args, env) do
    case sibling_ctors(env, name) do
      [] ->
        leftover_product(List.duplicate(:anything, length(args)), args, env)
        |> Enum.map(&{:ctor, name, &1})

      siblings ->
        Enum.flat_map(siblings, fn {sib, arity} ->
          if sib == short(name) or sib == name do
            sketches = pad_sketches(arity, args)

            leftover_product(sketches, pad_args(arity, args), env)
            |> Enum.map(&{:ctor, sib, &1})
          else
            [{:ctor, sib, List.duplicate(:anything, arity)}]
          end
        end)
    end
  end

  defp pad_sketches(arity, _args) when arity <= 0, do: []
  defp pad_sketches(arity, args), do: List.duplicate(:anything, max(arity, length(args))) |> Enum.take(arity)

  defp pad_args(arity, _args) when arity <= 0, do: []

  defp pad_args(arity, args) do
    args ++ List.duplicate(:wild, max(arity - length(args), 0))
    |> Enum.take(arity)
  end

  defp leftover_product([], [], _env), do: []

  defp leftover_product(sketches, patterns, _env)
       when length(sketches) != length(patterns) do
    []
  end

  defp leftover_product(sketches, patterns, env) do
    n = length(sketches)

    0..(n - 1)
    |> Enum.flat_map(fn i ->
      {before_s, [si | after_s]} = Enum.split(sketches, i)
      {before_p, [pi | _]} = Enum.split(patterns, i)

      covered_before =
        Enum.zip(before_s, before_p)
        |> Enum.map(fn {s, p} -> refine(s, p, env) end)

      if Enum.any?(covered_before, &(&1 == :empty)) do
        []
      else
        leftover_after([si], denorm(pi), env)
        |> Enum.map(fn li -> covered_before ++ [li] ++ after_s end)
      end
    end)
  end

  defp refine(_sketch, :wild, _env), do: :anything
  defp refine(sketch, {:as, inner}, env), do: refine(sketch, inner, env)
  defp refine(:anything, {:ctor, name, args}, env), do: {:ctor, short(name), Enum.map(args, &refine(:anything, &1, env))}
  defp refine(:anything, {:tuple, args}, env), do: {:tuple, Enum.map(args, &refine(:anything, &1, env))}
  defp refine(:anything, :nil, _env), do: :nil
  defp refine(:anything, {:cons, h, t}, env), do: {:cons, refine(:anything, h, env), refine(:anything, t, env)}
  defp refine(:anything, {:list, []}, _env), do: :nil
  defp refine(:anything, {:list, elems}, env), do: refine(:anything, list_as_cons(elems), env)
  defp refine(:anything, {:lit, k, v}, _env), do: {:lit, k, v}
  defp refine({:ctor, n, ps}, {:ctor, n, as}, env), do: {:ctor, n, Enum.zip(ps, as) |> Enum.map(fn {s, p} -> refine(s, p, env) end)}
  defp refine({:ctor, n, ps}, {:ctor, m, as}, env) do
    if short(n) == short(m) do
      {:ctor, short(n), Enum.zip(ps, as) |> Enum.map(fn {s, p} -> refine(s, p, env) end)}
    else
      :empty
    end
  end
  defp refine(sketch, _pattern, _env), do: sketch

  defp list_as_cons([]), do: :nil

  defp list_as_cons([head | tail]) do
    {:cons, norm_arg(head), list_as_cons(tail)}
  end

  defp sibling_ctors(env, name) do
    short = short(name)

    case Env.lookup_ctor(env, name) || Env.lookup_ctor(env, short) do
      %{union: union} ->
        env.constructors
        |> Map.values()
        |> Enum.filter(&(&1.union == union))
        |> Enum.uniq_by(&{&1.name, &1.arity})
        |> Enum.map(&{short(&1.name), &1.arity})

      _ ->
        cond do
          short in ["Just", "Nothing"] -> [{"Just", 1}, {"Nothing", 0}]
          short in ["Ok", "Err"] -> [{"Ok", 1}, {"Err", 1}]
          short in ["True", "False"] -> [{"True", 0}, {"False", 0}]
          short in ["::", "[]"] -> [{"::", 2}, {"[]", 0}]
          true -> []
        end
    end
  end

  defp norm(%{kind: :unknown, source: source}, env) do
    case recover(source) do
      {:ok, recovered} -> norm(recovered, env)
      :error -> :unknown
    end
  end

  defp norm(pat, env), do: do_norm(pat, env)

  defp do_norm(%{kind: :wildcard}, _env), do: :wild
  defp do_norm(%{kind: :var}, _env), do: :wild

  defp do_norm(%{kind: :alias, pattern: inner}, env) do
    {:as, do_norm(inner, env)}
  end

  defp do_norm(%{kind: :constructor, name: name} = pat, env) do
    arg = Map.get(pat, :arg_pattern)
    bind = Map.get(pat, :bind)
    ctor_name = short(name)
    ctor_name = if String.contains?(to_string(name), "."), do: name, else: ctor_name

    inner =
      cond do
        ctor_name in ["[]", "Nil"] or short(name) in ["[]", "Nil"] ->
          :nil

        short(name) == "::" ->
          case arg do
            %{kind: :tuple, elements: [h, t]} -> {:cons, do_norm(h, env), do_norm(t, env)}
            _ -> {:cons, :wild, :wild}
          end

        is_map(arg) ->
          {:ctor, ctor_name, ctor_payload_sketches(arg, name, env)}

        is_binary(bind) ->
          {:ctor, ctor_name, [:wild]}

        true ->
          {:ctor, ctor_name, []}
      end

    if is_binary(bind) and is_map(arg) do
      {:as, inner}
    else
      inner
    end
  end

  defp do_norm(%{kind: :tuple, elements: elems}, env) do
    {:tuple, Enum.map(elems || [], &do_norm(&1, env))}
  end

  defp do_norm(%{kind: :cons, head: head, tail: tail}, env) do
    {:cons, do_norm(head, env), do_norm(tail, env)}
  end

  defp do_norm(%{kind: :list, elements: elems}, env) do
    {:list, Enum.map(elems || [], &do_norm(&1, env))}
  end

  defp do_norm(%{kind: :int, value: v}, _env), do: {:lit, :int, v}
  defp do_norm(%{kind: :char, value: v}, _env), do: {:lit, :char, v}
  defp do_norm(%{kind: :string, value: v}, _env), do: {:lit, :string, v}
  defp do_norm(%{kind: :record}, _env), do: :wild
  defp do_norm(_, _env), do: :wild

  defp ctor_payload_sketches(arg, name, env) do
    arity = ctor_arity(env, name)
    flat = flatten_right_pair_pattern_maps(arg)

    cond do
      arity > 1 and length(flat) == arity ->
        Enum.map(flat, &do_norm(&1, env))

      true ->
        case arg do
          %{kind: :tuple, elements: elems} -> Enum.map(elems || [], &do_norm(&1, env))
          _ -> [do_norm(arg, env)]
        end
    end
  end

  defp flatten_right_pair_pattern_maps(%{kind: :tuple, elements: [left, right]}) do
    flatten_right_pair_pattern_maps(left) ++ flatten_right_pair_pattern_maps(right)
  end

  defp flatten_right_pair_pattern_maps(pat) when is_map(pat), do: [pat]
  defp flatten_right_pair_pattern_maps(_), do: []

  defp ctor_arity(env, name) when is_map(env) do
    case Env.lookup_ctor(env, name) || Env.lookup_ctor(env, short(name)) do
      %{arity: n} -> n
      _ -> 0
    end
  end

  defp ctor_arity(_, _), do: 0

  defp norm_arg(pat) when is_map(pat), do: do_norm(pat, nil)
  defp norm_arg(other), do: do_norm(other, nil)

  defp denorm(:wild), do: %{kind: :wildcard}
  defp denorm({:as, inner}), do: %{kind: :alias, pattern: denorm(inner)}
  defp denorm({:ctor, name, []}), do: %{kind: :constructor, name: name}
  defp denorm({:ctor, name, [:wild]}), do: %{kind: :constructor, name: name, bind: "_"}
  defp denorm({:ctor, name, args}), do: %{kind: :constructor, name: name, arg_pattern: denorm_args(args)}
  defp denorm({:tuple, args}), do: %{kind: :tuple, elements: Enum.map(args, &denorm/1)}
  defp denorm(:nil), do: %{kind: :list, elements: []}
  defp denorm({:cons, h, t}), do: %{kind: :cons, head: denorm(h), tail: denorm(t)}
  defp denorm({:list, elems}), do: %{kind: :list, elements: Enum.map(elems, &denorm/1)}
  defp denorm({:lit, :int, v}), do: %{kind: :int, value: v}
  defp denorm({:lit, :char, v}), do: %{kind: :char, value: v}
  defp denorm({:lit, :string, v}), do: %{kind: :string, value: v}
  defp denorm(:unknown), do: %{kind: :wildcard}
  defp denorm(_), do: %{kind: :wildcard}

  defp denorm_args([only]), do: denorm(only)
  defp denorm_args(args), do: %{kind: :tuple, elements: Enum.map(args, &denorm/1)}

  defp format_sketch(:anything), do: "_"
  defp format_sketch(:unknown), do: "_"
  defp format_sketch(:nil), do: "[]"
  defp format_sketch({:except_lits, _}), do: "_"
  defp format_sketch({:cons, h, t}), do: "#{format_sketch(h)} :: #{format_sketch(t)}"
  defp format_sketch({:ctor, name, []}), do: name
  defp format_sketch({:ctor, name, args}), do: name <> " " <> Enum.map_join(args, " ", &format_arg/1)
  defp format_sketch({:tuple, args}), do: "(" <> Enum.map_join(args, ", ", &format_sketch/1) <> ")"
  defp format_sketch({:list, []}), do: "[]"
  defp format_sketch({:list, elems}), do: "[" <> Enum.map_join(elems, ", ", &format_sketch/1) <> "]"
  defp format_sketch({:lit, _, v}), do: to_string(v)
  defp format_sketch(_), do: "_"

  defp format_arg({:ctor, _, [_ | _]} = sketch), do: "(" <> format_sketch(sketch) <> ")"
  defp format_arg({:cons, _, _} = sketch), do: "(" <> format_sketch(sketch) <> ")"
  defp format_arg(other), do: format_sketch(other)

  defp short(name) when is_binary(name), do: name |> String.split(".") |> List.last()
  defp short(name), do: name

  defp unwrap_grouping_parens("(" <> rest = full) do
    if String.ends_with?(rest, ")") do
      inner = String.slice(rest, 0, max(byte_size(rest) - 1, 0))

      if grouping_inner?(inner) do
        unwrap_grouping_parens(String.trim(inner))
      else
        full
      end
    else
      full
    end
  end

  defp unwrap_grouping_parens(source), do: source

  defp grouping_inner?(inner), do: not top_level_char?(inner, ",")

  defp top_level_char?(source, wanted) do
    source
    |> String.graphemes()
    |> Enum.reduce_while({0, 0, false}, fn
      "(", {paren, brace, _} -> {:cont, {paren + 1, brace, false}}
      ")", {paren, brace, _} -> {:cont, {max(paren - 1, 0), brace, false}}
      "{", {paren, brace, _} -> {:cont, {paren, brace + 1, false}}
      "}", {paren, brace, _} -> {:cont, {paren, max(brace - 1, 0), false}}
      "[", {paren, brace, _} -> {:cont, {paren, brace + 1, false}}
      "]", {paren, brace, _} -> {:cont, {paren, max(brace - 1, 0), false}}
      ^wanted, {0, 0, _} -> {:halt, {0, 0, true}}
      _, {paren, brace, _} -> {:cont, {paren, brace, false}}
    end)
    |> elem(2)
  end

  defp parse_pattern(source) do
    source = String.trim(source)

    case split_as(source) do
      {:ok, inner, name} ->
        case parse_pattern(inner) do
          {:ok, pat, ""} -> {:ok, %{kind: :alias, pattern: pat, bind: name}, ""}
          _ -> :error
        end

      :none ->
        parse_cons(source)
    end
  end

  defp split_as(source) do
    case Regex.run(~r/^(.*)\s+as\s+([a-z][A-Za-z0-9_]*)$/us, source) do
      [_, inner, name] -> {:ok, String.trim(inner), name}
      _ -> :none
    end
  end

  defp parse_cons(source) do
    case split_top(source, "::") do
      {:ok, left, right} ->
        with {:ok, head, ""} <- parse_pattern(left),
             {:ok, tail, ""} <- parse_pattern(right) do
          {:ok, %{kind: :cons, head: head, tail: tail}, ""}
        else
          _ -> :error
        end

      :none ->
        parse_atom_pattern(source)
    end
  end

  defp parse_atom_pattern(source) do
    source = String.trim(source)

    cond do
      source == "_" ->
        {:ok, %{kind: :wildcard}, ""}

      source == "[]" ->
        {:ok, %{kind: :list, elements: []}, ""}

      String.starts_with?(source, "(") ->
        parse_paren_pattern(String.trim_leading(String.slice(source, 1..-1//1)))

      String.starts_with?(source, "{") ->
        parse_record_pattern(String.trim_leading(String.slice(source, 1..-1//1)))

      String.starts_with?(source, "[") ->
        parse_list_pattern(String.trim_leading(String.slice(source, 1..-1//1)))

      String.starts_with?(source, "'") ->
        case Regex.run(~r/^'(.)'/, source) do
          [full, ch] -> {:ok, %{kind: :char, value: :binary.first(ch)}, String.slice(source, byte_size(full)..-1//1)}
          _ -> :error
        end

      String.starts_with?(source, "\"") ->
        case Regex.run(~r/^"([^"]*)"/, source) do
          [full, s] -> {:ok, %{kind: :string, value: s}, String.slice(source, byte_size(full)..-1//1)}
          _ -> :error
        end

      Regex.match?(~r/^-?\d+$/, source) ->
        {:ok, %{kind: :int, value: String.to_integer(source)}, ""}

      true ->
        parse_named_pattern(source)
    end
  end

  defp parse_named_pattern(source) do
    case Regex.run(~r/^([A-Za-z_][A-Za-z0-9_']*(?:\.[A-Za-z_][A-Za-z0-9_']*)*)/, source) do
      [full, name] ->
        rest = String.trim_leading(String.slice(source, byte_size(full)..-1//1))

        cond do
          String.match?(name, ~r/^[a-z]/) ->
            {:ok, %{kind: :var, name: name}, rest}

          rest == "" ->
            {:ok, %{kind: :constructor, name: name}, ""}

          true ->
            case parse_ctor_pattern_args(rest) do
              {:ok, [arg], more} ->
                {:ok, %{kind: :constructor, name: name, arg_pattern: arg}, more}

              {:ok, args, more} when args != [] ->
                {:ok, %{kind: :constructor, name: name, arg_pattern: nest_right_patterns(args)}, more}

              _ ->
                {:ok, %{kind: :constructor, name: name}, rest}
            end
        end

      _ ->
        :error
    end
  end

  defp parse_ctor_pattern_args(source) do
    parse_ctor_pattern_args(String.trim_leading(source), [])
  end

  defp parse_ctor_pattern_args("", acc), do: {:ok, Enum.reverse(acc), ""}

  defp parse_ctor_pattern_args(source, acc) do
    rest = String.trim_leading(source)

    cond do
      rest == "" or String.starts_with?(rest, ")") or String.starts_with?(rest, ",") or
          String.starts_with?(rest, "]") ->
        {:ok, Enum.reverse(acc), rest}

      true ->
        case parse_atom_pattern(rest) do
          {:ok, arg, more} ->
            parse_ctor_pattern_args(more, [arg | acc])

          :error ->
            {:ok, Enum.reverse(acc), rest}
        end
    end
  end

  defp nest_right_patterns([only]), do: only
  defp nest_right_patterns([first | rest]), do: %{kind: :tuple, elements: [first, nest_right_patterns(rest)]}
  defp nest_right_patterns([]), do: %{kind: :wildcard}

  defp parse_paren_pattern(source) do
    with {:ok, first, rest} <- parse_pattern(source) do
      rest = String.trim_leading(rest)

      cond do
        String.starts_with?(rest, ")") ->
          {:ok, first, String.trim_leading(String.slice(rest, 1..-1//1))}

        String.starts_with?(rest, ",") ->
          parse_tuple_elems([first], String.trim_leading(String.slice(rest, 1..-1//1)))

        true ->
          :error
      end
    end
  end

  defp parse_tuple_elems(acc, source) do
    with {:ok, elem, rest} <- parse_pattern(source) do
      acc = acc ++ [elem]
      rest = String.trim_leading(rest)

      cond do
        String.starts_with?(rest, ",") ->
          parse_tuple_elems(acc, String.trim_leading(String.slice(rest, 1..-1//1)))

        String.starts_with?(rest, ")") ->
          {:ok, %{kind: :tuple, elements: acc}, String.trim_leading(String.slice(rest, 1..-1//1))}

        true ->
          :error
      end
    end
  end

  defp parse_record_pattern(source) do
    parse_record_fields([], String.trim_leading(source))
  end

  defp parse_record_fields(acc, source) do
    rest = String.trim_leading(source)

    cond do
      String.starts_with?(rest, "}") ->
        {:ok, %{kind: :record, fields: acc}, String.trim_leading(String.slice(rest, 1..-1//1))}

      true ->
        case Regex.run(~r/^([a-z_][A-Za-z0-9_]*)/, rest) do
          [full, name] ->
            more = String.trim_leading(String.slice(rest, byte_size(full)..-1//1))
            acc = acc ++ [name]

            cond do
              String.starts_with?(more, ",") ->
                parse_record_fields(acc, String.trim_leading(String.slice(more, 1..-1//1)))

              String.starts_with?(more, "}") ->
                {:ok, %{kind: :record, fields: acc},
                 String.trim_leading(String.slice(more, 1..-1//1))}

              true ->
                :error
            end

          _ ->
            :error
        end
    end
  end

  defp parse_list_pattern("]" <> rest), do: {:ok, %{kind: :list, elements: []}, String.trim_leading(rest)}

  defp parse_list_pattern(source) do
    parse_list_elems([], source)
  end

  defp parse_list_elems(acc, source) do
    with {:ok, elem, rest} <- parse_pattern(source) do
      acc = acc ++ [elem]
      rest = String.trim_leading(rest)

      cond do
        String.starts_with?(rest, ",") ->
          parse_list_elems(acc, String.trim_leading(String.slice(rest, 1..-1//1)))

        String.starts_with?(rest, "]") ->
          {:ok, %{kind: :list, elements: acc}, String.trim_leading(String.slice(rest, 1..-1//1))}

        true ->
          :error
      end
    end
  end

  defp split_top(source, sep) do
    case do_split_top(String.graphemes(source), sep, 0, []) do
      {:ok, left, right} -> {:ok, String.trim(left), String.trim(right)}
      :none -> :none
    end
  end

  defp do_split_top([], _sep, _depth, _acc), do: :none

  defp do_split_top(["(" | rest], sep, depth, acc), do: do_split_top(rest, sep, depth + 1, acc ++ ["("])
  defp do_split_top([")" | rest], sep, depth, acc), do: do_split_top(rest, sep, max(depth - 1, 0), acc ++ [")"])
  defp do_split_top(["[" | rest], sep, depth, acc), do: do_split_top(rest, sep, depth + 1, acc ++ ["["])
  defp do_split_top(["]" | rest], sep, depth, acc), do: do_split_top(rest, sep, max(depth - 1, 0), acc ++ ["]"])

  defp do_split_top([a, b | rest], "::", 0, acc) when a == ":" and b == ":" do
    {:ok, Enum.join(acc), Enum.join(rest)}
  end

  defp do_split_top([ch | rest], sep, depth, acc), do: do_split_top(rest, sep, depth, acc ++ [ch])

  defp loc(mod, decl) do
    span = Map.get(decl, :span) || %{}

    [
      module: mod.name,
      function: Map.get(decl, :name),
      file: Map.get(mod, :path),
      line: Map.get(span, :start_line)
    ]
  end
end
