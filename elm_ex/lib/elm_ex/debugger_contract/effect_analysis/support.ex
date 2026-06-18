defmodule ElmEx.DebuggerContract.EffectAnalysis.Support do
  @moduledoc false

  alias ElmEx.Frontend.Module
  alias ElmEx.DebuggerContract.Types

  @spec view_type_name(Types.ast_expr() | String.t()) :: String.t()
  def view_type_name(target) when is_binary(target) do
    case String.split(target, ".") |> List.last() do
      nil -> target
      last -> last
    end
  end

  def init_case_subjects(init_params) when is_list(init_params) do
    init_params
    |> Enum.filter(&(is_binary(&1) and &1 != "" and &1 != "_"))
    |> Enum.uniq()
  end

  @spec init_case_subject_allowed?(
          Types.case_subject(),
          Types.param_list(),
          Types.param_list(),
          Types.binding_map()
        ) ::
          boolean()
  def init_case_subject_allowed?(subj, allowed, init_params, bindings)
      when is_list(allowed) and is_list(init_params) and is_map(bindings) do
    case ElmEx.DebuggerContract.case_subject_text(subj, bindings) do
      text when is_binary(text) and text != "" ->
        text in allowed or
          Enum.any?(init_params, fn p ->
            is_binary(p) and p != "_" and p != "" and String.starts_with?(text, p <> ".")
          end)

      _ ->
        false
    end
  end

  def update_case_subject_allowed?(subj, allowed, update_params, bindings)
      when is_list(allowed) and is_list(update_params) and is_map(bindings) do
    case ElmEx.DebuggerContract.case_subject_text(subj, bindings) do
      "" ->
        false

      text ->
        text in allowed or
          Enum.any?(update_params, fn p ->
            is_binary(p) and p != "_" and p != "" and String.starts_with?(text, p <> ".")
          end)
    end
  end

  @spec update_case_subjects(Types.param_list()) :: Types.param_list()
  def update_case_subjects(update_params) when is_list(update_params) do
    base = ["msg", "message"]

    case List.first(update_params) do
      first when is_binary(first) and first != "" and first != "_" ->
        Enum.uniq([first | base])

      _ ->
        base
    end
  end

  def peel_lets(%{op: :let_in, in_expr: inner}), do: peel_lets(inner)
  def peel_lets(other), do: other
  def inline_let_bindings(expr, _bindings, _seen, depth) when depth > 12, do: expr

  def inline_let_bindings(%{op: :var, name: name}, bindings, seen, depth)
      when is_binary(name) and is_map(bindings) do
    if MapSet.member?(seen, name) do
      %{op: :var, name: name}
    else
      case Map.get(bindings, name) do
        nil ->
          %{op: :var, name: name}

        expr ->
          expr
          |> inline_let_bindings(bindings, MapSet.put(seen, name), depth + 1)
      end
    end
  end

  def inline_let_bindings(%{op: :constructor_call} = expr, bindings, seen, depth) do
    Map.update!(expr, :args, fn args ->
      Enum.map(args, &inline_let_bindings(&1, bindings, seen, depth + 1))
    end)
  end

  def inline_let_bindings(%{op: :qualified_call} = expr, bindings, seen, depth) do
    Map.update!(expr, :args, fn args ->
      Enum.map(args, &inline_let_bindings(&1, bindings, seen, depth + 1))
    end)
  end

  def inline_let_bindings(%{op: :call} = expr, bindings, seen, depth) do
    Map.update!(expr, :args, fn args ->
      Enum.map(args, &inline_let_bindings(&1, bindings, seen, depth + 1))
    end)
  end

  def inline_let_bindings(%{op: :field_access, arg: arg} = expr, bindings, seen, depth) do
    Map.put(
      expr,
      :arg,
      cond do
        is_binary(arg) ->
          inline_let_bindings(%{op: :var, name: arg}, bindings, seen, depth + 1)

        is_map(arg) ->
          inline_let_bindings(arg, bindings, seen, depth + 1)

        true ->
          arg
      end
    )
  end

  def inline_let_bindings(%{op: :list_literal} = expr, bindings, seen, depth) do
    Map.update!(expr, :items, fn xs ->
      Enum.map(xs, &inline_let_bindings(&1, bindings, seen, depth + 1))
    end)
  end

  def inline_let_bindings(%{op: :tuple2, left: left, right: right}, bindings, seen, depth) do
    %{
      op: :tuple2,
      left: inline_let_bindings(left, bindings, seen, depth + 1),
      right: inline_let_bindings(right, bindings, seen, depth + 1)
    }
  end

  def inline_let_bindings(expr, _bindings, _seen, _depth), do: expr

  @spec expr_to_json_value(
          Types.ast_expr(),
          non_neg_integer(),
          non_neg_integer(),
          Types.module_ref() | nil
        ) ::
          Types.json_value()
  def expr_to_json_value(expr, depth, max, mod \\ nil)

  def expr_to_json_value(%{op: :record_literal, fields: fields}, depth, max, mod)
      when depth < max do
    Enum.into(fields, %{}, fn %{name: n, expr: e} ->
      {n, expr_to_json_value(e, depth + 1, max, mod)}
    end)
  end

  def expr_to_json_value(%{op: :int_literal, value: v}, _, _, _), do: v

  def expr_to_json_value(%{op: :string_literal, value: v}, _, _, _), do: v

  def expr_to_json_value(%{op: :char_literal, value: v}, _, _, _), do: v

  def expr_to_json_value(%{op: :constructor_call, target: t, args: args}, depth, max, mod)
      when depth < max do
    %{
      "$ctor" => t,
      "$args" => Enum.map(args, &expr_to_json_value(&1, depth + 1, max, mod))
    }
  end

  def expr_to_json_value(%{op: :qualified_call, target: t, args: args}, depth, max, mod)
      when depth < max do
    %{"$call" => t, "$args" => Enum.map(args, &expr_to_json_value(&1, depth + 1, max, mod))}
  end

  def expr_to_json_value(%{op: :call, name: name, args: args}, depth, max, mod)
      when is_binary(name) and depth < max do
    %{"$call" => name, "$args" => Enum.map(args, &expr_to_json_value(&1, depth + 1, max, mod))}
  end

  def expr_to_json_value(%{op: :var, name: n}, depth, max, %Module{} = mod) do
    case ElmEx.DebuggerContract.find_function_definition(mod, n) do
      %{expr: expr} when is_map(expr) -> expr_to_json_value(expr, depth, max, mod)
      _ -> %{"$var" => n}
    end
  end

  def expr_to_json_value(%{op: :var, name: n}, _, _, _), do: %{"$var" => n}

  def expr_to_json_value(%{op: :field_access, arg: arg, field: field}, depth, max, mod)
      when is_binary(field) and depth < max do
    on_expr =
      cond do
        is_binary(arg) -> %{"$var" => arg}
        is_map(arg) -> expr_to_json_value(arg, depth + 1, max, mod)
        true -> %{"$opaque" => true}
      end

    %{"$field" => field, "$on" => on_expr}
  end

  def expr_to_json_value(%{op: :cmd_none}, _, _, _), do: %{"$ctor" => "Cmd.none", "$args" => []}

  def expr_to_json_value(%{op: :list_literal, items: items}, depth, max, mod) when depth < max do
    Enum.map(items, &expr_to_json_value(&1, depth + 1, max, mod))
  end

  def expr_to_json_value(%{op: :tuple2, left: l, right: r}, depth, max, mod) when depth < max do
    [expr_to_json_value(l, depth + 1, max, mod), expr_to_json_value(r, depth + 1, max, mod)]
  end

  def expr_to_json_value(%{op: :unsupported, source: s}, _, _, _) when is_binary(s) do
    %{"$opaque" => true, "preview" => String.slice(s, 0, 120)}
  end

  def expr_to_json_value(%{op: op}, _, _, _), do: %{"$opaque" => true, "op" => to_string(op)}

  def expr_to_json_value(_, _, _, _), do: %{"$opaque" => true}
  def peel_update_outer(%{op: :let_in, in_expr: inner}), do: peel_update_outer(inner)
  def peel_update_outer(other), do: other
  @spec pattern_constructor_name(Types.ast_expr()) :: String.t() | nil
  def pattern_constructor_name(%{kind: :constructor, name: n}) when is_binary(n), do: n
  def pattern_constructor_name(_), do: nil

  @spec record_update_param_field_map(Types.ast_expr(), Types.binding_map()) :: %{
          String.t() => String.t()
        }
  def record_update_param_field_map(body, bindings) when is_map(bindings) do
    body
    |> peel_lets()
    |> peel_update_result_model()
    |> then(fn
      fields when is_list(fields) -> param_to_model_field_map(fields, bindings)
      _ -> %{}
    end)
  end

  def record_update_param_field_map(_body, _bindings), do: %{}

  @spec peel_update_result_model(Types.ast_expr()) :: Types.ast_expr() | nil
  defp peel_update_result_model(%{op: :tuple2, left: left}), do: peel_update_result_model(left)

  defp peel_update_result_model(%{
         op: :record_update,
         base: %{op: :var, name: base},
         fields: fields
       })
       when base in ["model", "state"] and is_list(fields),
       do: fields

  defp peel_update_result_model(_), do: nil

  @spec param_to_model_field_map(list(), Types.binding_map()) :: %{String.t() => String.t()}
  defp param_to_model_field_map(fields, bindings) when is_list(fields) and is_map(bindings) do
    Enum.reduce(fields, %{}, fn
      %{name: field, expr: %{op: :var, name: param}}, acc
      when is_binary(field) and is_binary(param) ->
        Map.put(acc, param, field)

      %{name: field, value: %{op: :var, name: param}}, acc
      when is_binary(field) and is_binary(param) ->
        Map.put(acc, param, field)

      _, acc ->
        acc
    end)
  end

  defp param_to_model_field_map(_fields, _bindings), do: %{}
end
