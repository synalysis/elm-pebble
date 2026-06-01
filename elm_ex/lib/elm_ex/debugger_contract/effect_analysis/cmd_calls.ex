defmodule ElmEx.DebuggerContract.EffectAnalysis.CmdCalls do
  @moduledoc false

  alias ElmEx.Frontend.Module
  alias ElmEx.DebuggerContract.Types
  alias ElmEx.DebuggerContract.EffectAnalysis.Subscriptions
  alias ElmEx.DebuggerContract.EffectAnalysis.Support

  @spec init_cmd_ops_outline(Types.ast_expr() | nil, Types.param_list()) :: Types.string_list()
  def init_cmd_ops_outline(nil, _), do: []

  def init_cmd_ops_outline(expr, init_params) when is_list(init_params) do
    allowed = Support.init_case_subjects(init_params)

    {peeled, bindings} = ElmEx.DebuggerContract.peel_lets_with_bindings(expr)

    case peeled do
      %{op: :case, subject: subj, branches: branches} when is_list(branches) ->
        if Support.init_case_subject_allowed?(subj, allowed, init_params, bindings) do
          Enum.flat_map(branches, fn
            %{expr: e} -> cmd_ops_from_case_branch_expr(e)
            _ -> []
          end)
        else
          []
        end

      %{op: :tuple2, right: right} ->
        right |> Support.peel_lets() |> extract_cmd_op_items()

      _ ->
        []
    end
  end

  def init_cmd_ops_outline(_, _), do: []

  @spec init_cmd_calls_outline(Types.ast_expr() | nil, Types.param_list()) :: Types.cmd_call_list()
  def init_cmd_calls_outline(nil, _), do: []

  def init_cmd_calls_outline(expr, init_params) when is_list(init_params) do
    allowed = Support.init_case_subjects(init_params)

    {peeled, bindings} = ElmEx.DebuggerContract.peel_lets_with_bindings(expr)

    calls =
      case peeled do
        %{op: :case, subject: subj, branches: branches} when is_list(branches) ->
          if Support.init_case_subject_allowed?(subj, allowed, init_params, bindings) do
            Enum.flat_map(branches, fn
              %{expr: e} -> cmd_calls_from_case_branch_expr(e)
              _ -> []
            end)
          else
            []
          end

        %{op: :tuple2, right: right} ->
          extract_cmd_calls(right, bindings)

        _ ->
          []
      end

    Enum.uniq_by(calls, &{&1["name"], &1["callback_constructor"], &1["target"]})
  end

  def init_cmd_calls_outline(_, _), do: []

  @spec update_cmd_ops_outline(Types.ast_expr() | nil, Types.param_list()) :: Types.string_list()
  def update_cmd_ops_outline(nil, _), do: []

  def update_cmd_ops_outline(expr, update_params) when is_list(update_params) do
    allowed = Support.update_case_subjects(update_params)

    expr
    |> Support.peel_update_outer()
    |> case do
      %{op: :case, subject: subj, branches: branches} when is_list(branches) ->
        if Support.update_case_subject_allowed?(subj, allowed, update_params, %{}) do
          Enum.flat_map(branches, fn
            %{expr: e} -> cmd_ops_from_case_branch_expr(e)
            _ -> []
          end)
        else
          []
        end

      %{op: :tuple2, right: right} ->
        right |> Support.peel_lets() |> extract_cmd_op_items()

      _ ->
        []
    end
  end

  def update_cmd_ops_outline(_, _), do: []

  @spec update_cmd_calls_outline(Types.ast_expr() | nil, Types.param_list()) :: Types.cmd_call_list()
  def update_cmd_calls_outline(nil, _), do: []

  def update_cmd_calls_outline(expr, update_params) when is_list(update_params) do
    allowed = Support.update_case_subjects(update_params)

    calls =
      expr
      |> Support.peel_update_outer()
      |> case do
        %{op: :case, subject: subj, branches: branches} when is_list(branches) ->
          if Support.update_case_subject_allowed?(subj, allowed, update_params, %{}) do
            Enum.flat_map(branches, fn
              %{pattern: p, expr: e} ->
                branch_label = ElmEx.DebuggerContract.pattern_branch_label(p)
                branch_constructor = Support.pattern_constructor_name(p)

                e
                |> cmd_calls_from_case_branch_expr()
                |> Enum.map(fn row ->
                  row
                  |> Map.put("branch", branch_label)
                  |> maybe_put_branch_constructor(branch_constructor)
                end)

              %{expr: e} ->
                cmd_calls_from_case_branch_expr(e)

              _ ->
                []
            end)
          else
            []
          end

        %{op: :tuple2, right: right} ->
          extract_cmd_calls(right)

        _ ->
          []
      end

    Enum.uniq_by(
      calls,
      &{&1["name"], &1["callback_constructor"], &1["target"], &1["branch_constructor"]}
    )
  end

  def update_cmd_calls_outline(_, _), do: []

  @spec cmd_ops_from_case_branch_expr(Types.ast_expr()) :: Types.string_list()
  def cmd_ops_from_case_branch_expr(expr) do
    expr
    |> Support.peel_lets()
    |> case do
      %{op: :tuple2, right: right} ->
        right |> Support.peel_lets() |> extract_cmd_op_items()

      _ ->
        []
    end
  end

  @spec cmd_calls_from_case_branch_expr(Types.ast_expr()) :: Types.cmd_call_list()
  def cmd_calls_from_case_branch_expr(expr) do
    {peeled, bindings} = ElmEx.DebuggerContract.peel_lets_with_bindings(expr)

    case peeled do
      %{op: :tuple2, right: right} ->
        extract_cmd_calls(right, bindings)

      _ ->
        extract_cmd_calls(peeled, bindings)
    end
  end

  @spec maybe_put_branch_constructor(Types.cmd_call_row(), String.t()) :: Types.cmd_call_row()
  def maybe_put_branch_constructor(row, constructor)
       when is_map(row) and is_binary(constructor) and constructor != "" do
    Map.put(row, "branch_constructor", constructor)
  end

  def maybe_put_branch_constructor(row, _constructor), do: row
  def extract_cmd_op_items(%{
         op: :qualified_call,
         args: [%{op: :list_literal, items: items}]
       })
       when is_list(items) do
    Enum.flat_map(items, &extract_cmd_op_items/1)
  end

  def extract_cmd_op_items(%{op: :qualified_call} = qc) do
    [Subscriptions.subscription_item_label(qc)]
  end

  def extract_cmd_op_items(%{
         op: :call,
         name: name,
         args: [%{op: :list_literal, items: items}]
       })
       when is_list(items) and is_binary(name) do
    items
    |> Enum.flat_map(&extract_cmd_op_items/1)
    |> then(fn xs -> if xs != [], do: xs, else: [name <> "(…)"] end)
  end

  def extract_cmd_op_items(%{op: :list_literal, items: items}) when is_list(items) do
    Enum.flat_map(items, &extract_cmd_op_items/1)
  end

  def extract_cmd_op_items(%{op: :if, then_expr: then_expr, else_expr: else_expr}) do
    extract_cmd_op_items(then_expr) ++ extract_cmd_op_items(else_expr)
  end

  def extract_cmd_op_items(expr) do
    case Subscriptions.subscription_item_label(expr) do
      nil -> []
      s -> [s]
    end
  end

  def extract_cmd_calls(expr), do: extract_cmd_calls(expr, %{})

  def extract_cmd_calls(
         %{
           op: :qualified_call,
           target: "Cmd.batch",
           args: [%{op: :list_literal, items: items}]
         },
         bindings
       )
       when is_list(items) and is_map(bindings) do
    Enum.flat_map(items, &extract_cmd_calls(&1, bindings))
  end

  def extract_cmd_calls(
         %{
           op: :qualified_call,
           target: target,
           args: args
         },
         bindings
       )
       when is_binary(target) and is_list(args) and is_map(bindings) do
    [
      %{
        "target" => target,
        "name" => Support.view_type_name(target),
        "callback_constructor" => callback_constructor_from_args(args, bindings),
        "callback_arg_count" => callback_arg_count_from_args(args, bindings),
        "arg_kinds" => Enum.map(args, &expr_arg_kind/1),
        "arg_snippets" => Enum.map(args, &Subscriptions.subscription_arg_snippet/1),
        "arg_values" =>
          Enum.map(args, fn arg ->
            arg
            |> Support.inline_let_bindings(bindings, MapSet.new(), 0)
            |> Support.expr_to_json_value(0, 4)
          end),
        "task_sources" => task_sources_from_args(args)
      }
    ]
  end

  def extract_cmd_calls(
         %{
           op: :call,
           name: name,
           args: args
         },
         bindings
       )
       when is_binary(name) and is_list(args) and is_map(bindings) do
    [
      %{
        "target" => name,
        "name" => Support.view_type_name(name),
        "callback_constructor" => callback_constructor_from_args(args, bindings),
        "callback_arg_count" => callback_arg_count_from_args(args, bindings),
        "arg_kinds" => Enum.map(args, &expr_arg_kind/1),
        "arg_snippets" => Enum.map(args, &Subscriptions.subscription_arg_snippet/1),
        "arg_values" =>
          Enum.map(args, fn arg ->
            arg
            |> Support.inline_let_bindings(bindings, MapSet.new(), 0)
            |> Support.expr_to_json_value(0, 4)
          end),
        "task_sources" => task_sources_from_args(args)
      }
    ]
  end

  def extract_cmd_calls(
         %{op: :let_in, name: name, value_expr: value_expr, in_expr: inner},
         bindings
       )
       when is_binary(name) and is_map(bindings) do
    extract_cmd_calls(inner, Map.put(bindings, name, value_expr))
  end

  def extract_cmd_calls(%{op: :let_in, in_expr: inner}, bindings) when is_map(bindings),
    do: extract_cmd_calls(inner, bindings)

  def extract_cmd_calls(%{op: :list_literal, items: items}, bindings)
       when is_list(items) and is_map(bindings),
       do: Enum.flat_map(items, &extract_cmd_calls(&1, bindings))

  def extract_cmd_calls(%{op: :var, name: name}, bindings)
       when is_binary(name) and is_map(bindings) do
    case Map.get(bindings, name) do
      nil ->
        [%{"target" => name, "name" => name}]

      expr ->
        extract_cmd_calls(expr, bindings)
    end
  end

  def extract_cmd_calls(%{op: :tuple2, right: right}, bindings) when is_map(bindings),
    do: extract_cmd_calls(right, bindings)

  def extract_cmd_calls(%{op: :case, branches: branches}, bindings)
       when is_list(branches) and is_map(bindings) do
    Enum.flat_map(branches, fn
      %{expr: expr} -> extract_cmd_calls(expr, bindings)
      _ -> []
    end)
  end

  def extract_cmd_calls(_, _), do: []

  @spec callback_constructor_from_args(list(), Types.binding_map()) :: String.t() | nil
  def callback_constructor_from_args(args, bindings)
       when is_list(args) and is_map(bindings) do
    args
    |> Enum.reverse()
    |> Enum.find_value(&callback_constructor_from_expr(&1, bindings, MapSet.new(), 0))
  end

  def callback_constructor_from_args(_, _), do: nil

  @spec callback_arg_count_from_args(list(), Types.binding_map()) :: non_neg_integer()
  def callback_arg_count_from_args(args, bindings)
       when is_list(args) and is_map(bindings) do
    args
    |> Enum.reverse()
    |> Enum.find_value(&callback_arg_count_from_expr(&1, bindings, MapSet.new(), 0))
    |> case do
      count when is_integer(count) and count >= 0 -> count
      _ -> 0
    end
  end

  def callback_arg_count_from_args(_, _), do: 0

  @spec callback_arg_count_from_expr(Types.ast_expr(), Types.binding_map(), MapSet.t(String.t()), non_neg_integer()) ::
          non_neg_integer() | nil
  def callback_arg_count_from_expr(_expr, _bindings, _seen, depth) when depth > 10, do: nil

  def callback_arg_count_from_expr(
         %{op: :constructor_call, args: args},
         _bindings,
         _seen,
         _depth
       )
       when is_list(args),
       do: length(args)

  def callback_arg_count_from_expr(%{op: :constructor_call}, _bindings, _seen, _depth), do: 0

  def callback_arg_count_from_expr(%{op: :var, name: name}, bindings, seen, depth)
       when is_binary(name) and is_map(bindings) do
    if MapSet.member?(seen, name) do
      nil
    else
      case Map.get(bindings, name) do
        nil -> nil
        expr -> callback_arg_count_from_expr(expr, bindings, MapSet.put(seen, name), depth + 1)
      end
    end
  end

  def callback_arg_count_from_expr(_, _, _, _), do: nil

  @spec task_sources_from_args([Types.ast_expr()]) :: [String.t()]
  def task_sources_from_args(args) when is_list(args) do
    args
    |> Enum.flat_map(&qualified_call_targets/1)
    |> Enum.uniq()
  end

  @spec qualified_call_targets(Types.ast_expr()) :: [String.t()]
  def qualified_call_targets(%{op: :qualified_call, target: target, args: args})
       when is_binary(target) and is_list(args) do
    [target | Enum.flat_map(args, &qualified_call_targets/1)]
  end

  def qualified_call_targets(%{op: :call, name: name, args: args})
       when is_binary(name) and is_list(args) do
    [name | Enum.flat_map(args, &qualified_call_targets/1)]
  end

  def qualified_call_targets(%{op: :constructor_call, args: args}) when is_list(args),
    do: Enum.flat_map(args, &qualified_call_targets/1)

  def qualified_call_targets(%{op: :lambda, body: body}), do: qualified_call_targets(body)

  def qualified_call_targets(%{op: :tuple2, left: left, right: right}),
    do: qualified_call_targets(left) ++ qualified_call_targets(right)

  def qualified_call_targets(%{op: :list_literal, items: items}) when is_list(items),
    do: Enum.flat_map(items, &qualified_call_targets/1)

  def qualified_call_targets(_), do: []

  @spec callback_preferred_over_result_mapper?(String.t() | nil) :: boolean()
  def callback_preferred_over_result_mapper?(ctor) when is_binary(ctor) do
    ctor not in ["Current", "Forecast"]
  end

  def callback_preferred_over_result_mapper?(_ctor), do: false

  @spec callback_constructor_from_expr(Types.ast_expr(), Types.binding_map(), MapSet.t(String.t()), non_neg_integer()) ::
          String.t() | nil
  def callback_constructor_from_expr(_expr, _bindings, _seen, depth) when depth > 10, do: nil

  def callback_constructor_from_expr(
         %{op: :constructor_call, target: target},
         _bindings,
         _seen,
         _depth
       )
       when is_binary(target),
       do: Support.view_type_name(target)

  def callback_constructor_from_expr(%{op: :var, name: name}, bindings, seen, depth)
       when is_binary(name) and is_map(bindings) do
    if MapSet.member?(seen, name) do
      nil
    else
      case Map.get(bindings, name) do
        nil -> if(constructor_like_name?(name), do: name, else: nil)
        expr -> callback_constructor_from_expr(expr, bindings, MapSet.put(seen, name), depth + 1)
      end
    end
  end

  def callback_constructor_from_expr(
         %{op: :record_literal, fields: fields},
         bindings,
         seen,
         depth
       )
       when is_list(fields) do
    expect_expr =
      Enum.find_value(fields, fn
        %{name: "expect", expr: expr} -> expr
        _ -> nil
      end)

    case callback_constructor_from_expr(expect_expr, bindings, seen, depth + 1) do
      nil ->
        Enum.find_value(fields, fn
          %{expr: expr} -> callback_constructor_from_expr(expr, bindings, seen, depth + 1)
          _ -> nil
        end)

      constructor ->
        constructor
    end
  end

  def callback_constructor_from_expr(%{op: :qualified_call, args: args}, bindings, seen, depth)
       when is_list(args) do
    Enum.find_value(args, &callback_constructor_from_expr(&1, bindings, seen, depth + 1))
  end

  def callback_constructor_from_expr(%{op: :call, name: name, args: args}, bindings, seen, depth)
       when is_binary(name) and is_list(args) do
    cond do
      constructor_like_name?(name) and callback_preferred_over_result_mapper?(name) ->
        Support.view_type_name(name)

      true ->
        Enum.find_value(args, &callback_constructor_from_expr(&1, bindings, seen, depth + 1))
    end
  end

  def callback_constructor_from_expr(%{op: :call, args: args}, bindings, seen, depth)
       when is_list(args) do
    Enum.find_value(args, &callback_constructor_from_expr(&1, bindings, seen, depth + 1))
  end

  def callback_constructor_from_expr(
         %{op: :let_in, name: name, value_expr: value_expr, in_expr: inner},
         bindings,
         seen,
         depth
       )
       when is_binary(name) and is_map(bindings) do
    next_bindings = Map.put(bindings, name, value_expr)
    callback_constructor_from_expr(inner, next_bindings, seen, depth + 1)
  end

  def callback_constructor_from_expr(
         %{op: :tuple2, left: left, right: right},
         bindings,
         seen,
         depth
       ) do
    left_ctor = callback_constructor_from_expr(left, bindings, seen, depth + 1)
    right_ctor = callback_constructor_from_expr(right, bindings, seen, depth + 1)

    cond do
      callback_preferred_over_result_mapper?(left_ctor) ->
        left_ctor

      is_binary(left_ctor) ->
        left_ctor

      is_binary(right_ctor) ->
        right_ctor

      true ->
        nil
    end
  end

  def callback_constructor_from_expr(%{op: :list_literal, items: items}, bindings, seen, depth)
       when is_list(items) do
    Enum.find_value(items, &callback_constructor_from_expr(&1, bindings, seen, depth + 1))
  end

  def callback_constructor_from_expr(_, _bindings, _seen, _depth), do: nil

  @spec constructor_like_name?(String.t()) :: boolean()
  def constructor_like_name?(name) when is_binary(name) do
    String.match?(name, ~r/^[A-Z][A-Za-z0-9_]*$/)
  end

  @spec expr_arg_kind(Types.ast_expr()) :: String.t()
  def expr_arg_kind(%{op: op}) when is_atom(op), do: Atom.to_string(op)
  def expr_arg_kind(_), do: "unknown"

  def function_cmd_calls(%Module{declarations: decls}) when is_list(decls) do
    decls
    |> Enum.filter(&match?(%{kind: :function_definition}, &1))
    |> Map.new(fn
      %{name: name, args: args, expr: expr} when is_binary(name) and is_list(args) ->
        calls =
          expr
          |> extract_cmd_calls()
          |> Enum.map(&Map.put(&1, "function_args", args))

        {name, calls}

      %{name: name} when is_binary(name) ->
        {name, []}
    end)
  end

  def function_cmd_calls(_), do: %{}
end
