defmodule Ide.Debugger.ElmIntrospect.EffectAnalysis do
  @moduledoc false

  alias ElmEx.Frontend.Module
  alias Ide.Debugger.ElmIntrospect
  alias Ide.Debugger.ElmIntrospect.Types
  alias Ide.Debugger.Types.CmdCall

  @spec view_type_name(Types.ast_expr() | String.t()) :: String.t()
  defp view_type_name(target) when is_binary(target) do
    case String.split(target, ".") |> List.last() do
      nil -> target
      last -> last
    end
  end

  def main_program_outline(nil), do: nil

  def main_program_outline(expr) do
    expr
    |> peel_lets()
    |> case do
      %{op: :qualified_call, target: t, args: args} when is_list(args) and args != [] ->
        record_fields =
          case hd(args) do
            %{op: :record_literal, fields: fs} when is_list(fs) ->
              fs
              |> Enum.map(fn %{name: n} -> n end)
              |> Enum.filter(&(is_binary(&1) and &1 != "_invalid"))

            _ ->
              []
          end

        %{
          "target" => t,
          "kind" => main_kind_from_target(t),
          "fields" => record_fields
        }

      _ ->
        nil
    end
  end

  @spec main_kind_from_target(String.t()) :: String.t()
  defp main_kind_from_target(t) when is_binary(t) do
    case view_type_name(t) do
      "worker" -> "worker"
      "element" -> "element"
      "document" -> "document"
      "sandbox" -> "sandbox"
      _ -> "unknown"
    end
  end

  @spec init_cmd_ops_outline(Types.ast_expr() | nil, Types.param_list()) :: Types.string_list()
  def init_cmd_ops_outline(nil, _), do: []

  def init_cmd_ops_outline(expr, init_params) when is_list(init_params) do
    allowed = init_case_subjects(init_params)

    {peeled, bindings} = ElmIntrospect.peel_lets_with_bindings(expr)

    case peeled do
      %{op: :case, subject: subj, branches: branches} when is_list(branches) ->
        if init_case_subject_allowed?(subj, allowed, init_params, bindings) do
          Enum.flat_map(branches, fn
            %{expr: e} -> cmd_ops_from_case_branch_expr(e)
            _ -> []
          end)
        else
          []
        end

      %{op: :tuple2, right: right} ->
        right |> peel_lets() |> extract_cmd_op_items()

      _ ->
        []
    end
  end

  def init_cmd_ops_outline(_, _), do: []

  @spec init_cmd_calls_outline(Types.ast_expr() | nil, Types.param_list()) :: Types.cmd_call_list()
  def init_cmd_calls_outline(nil, _), do: []

  def init_cmd_calls_outline(expr, init_params) when is_list(init_params) do
    allowed = init_case_subjects(init_params)

    {peeled, bindings} = ElmIntrospect.peel_lets_with_bindings(expr)

    calls =
      case peeled do
        %{op: :case, subject: subj, branches: branches} when is_list(branches) ->
          if init_case_subject_allowed?(subj, allowed, init_params, bindings) do
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
    allowed = update_case_subjects(update_params)

    expr
    |> peel_update_outer()
    |> case do
      %{op: :case, subject: subj, branches: branches} when is_list(branches) ->
        if update_case_subject_allowed?(subj, allowed, update_params, %{}) do
          Enum.flat_map(branches, fn
            %{expr: e} -> cmd_ops_from_case_branch_expr(e)
            _ -> []
          end)
        else
          []
        end

      %{op: :tuple2, right: right} ->
        right |> peel_lets() |> extract_cmd_op_items()

      _ ->
        []
    end
  end

  def update_cmd_ops_outline(_, _), do: []

  @spec update_cmd_calls_outline(Types.ast_expr() | nil, Types.param_list()) :: Types.cmd_call_list()
  def update_cmd_calls_outline(nil, _), do: []

  def update_cmd_calls_outline(expr, update_params) when is_list(update_params) do
    allowed = update_case_subjects(update_params)

    calls =
      expr
      |> peel_update_outer()
      |> case do
        %{op: :case, subject: subj, branches: branches} when is_list(branches) ->
          if update_case_subject_allowed?(subj, allowed, update_params, %{}) do
            Enum.flat_map(branches, fn
              %{pattern: p, expr: e} ->
                branch_label = ElmIntrospect.pattern_branch_label(p)
                branch_constructor = pattern_constructor_name(p)

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
  defp cmd_ops_from_case_branch_expr(expr) do
    expr
    |> peel_lets()
    |> case do
      %{op: :tuple2, right: right} ->
        right |> peel_lets() |> extract_cmd_op_items()

      _ ->
        []
    end
  end

  @spec cmd_calls_from_case_branch_expr(Types.ast_expr()) :: Types.cmd_call_list()
  defp cmd_calls_from_case_branch_expr(expr) do
    {peeled, bindings} = ElmIntrospect.peel_lets_with_bindings(expr)

    case peeled do
      %{op: :tuple2, right: right} ->
        extract_cmd_calls(right, bindings)

      _ ->
        extract_cmd_calls(peeled, bindings)
    end
  end

  @spec maybe_put_branch_constructor(Types.cmd_call_row(), String.t()) :: Types.cmd_call_row()
  defp maybe_put_branch_constructor(row, constructor)
       when is_map(row) and is_binary(constructor) and constructor != "" do
    Map.put(row, "branch_constructor", constructor)
  end

  defp maybe_put_branch_constructor(row, _constructor), do: row

  @spec subscriptions_outline(Types.ast_expr() | nil, Types.param_list()) :: Types.string_list()
  def subscriptions_outline(nil, _), do: []

  def subscriptions_outline(expr, subscriptions_params) when is_list(subscriptions_params) do
    allowed = init_case_subjects(subscriptions_params)
    {peeled, bindings} = ElmIntrospect.peel_lets_with_bindings(expr)

    case peeled do
      %{op: :case, subject: subj, branches: branches} when is_list(branches) ->
        if init_case_subject_allowed?(subj, allowed, subscriptions_params, bindings) do
          Enum.flat_map(branches, fn
            %{expr: e} -> e |> peel_lets() |> extract_subscription_items()
            _ -> []
          end)
        else
          extract_subscription_items(peeled)
        end

      _ ->
        extract_subscription_items(peeled)
    end
  end

  def subscriptions_outline(_, _), do: []

  @spec extract_subscription_items(Types.ast_expr()) :: Types.string_list()
  defp extract_subscription_items(%{
         op: :qualified_call,
         args: [%{op: :list_literal, items: items}]
       })
       when is_list(items) do
    items |> Enum.flat_map(&extract_subscription_items/1) |> Enum.uniq()
  end

  defp extract_subscription_items(%{op: :qualified_call} = qc) do
    [subscription_item_label(qc)]
  end

  defp extract_subscription_items(%{
         op: :call,
         name: name,
         args: [%{op: :list_literal, items: items}]
       })
       when is_list(items) and is_binary(name) do
    items
    |> Enum.flat_map(&extract_subscription_items/1)
    |> Enum.uniq()
    |> then(fn xs -> if xs != [], do: xs, else: [name <> "(…)"] end)
  end

  defp extract_subscription_items(%{op: :list_literal, items: items}) when is_list(items) do
    items |> Enum.flat_map(&extract_subscription_items/1) |> Enum.uniq()
  end

  defp extract_subscription_items(%{op: :if, then_expr: then_expr, else_expr: else_expr}) do
    extract_subscription_items(then_expr) ++ extract_subscription_items(else_expr)
    |> Enum.uniq()
  end

  defp extract_subscription_items(expr) do
    case subscription_item_label(expr) do
      nil -> []
      s -> [s]
    end
  end

  @spec extract_cmd_op_items(Types.ast_expr()) :: Types.string_list()
  defp extract_cmd_op_items(%{
         op: :qualified_call,
         args: [%{op: :list_literal, items: items}]
       })
       when is_list(items) do
    Enum.flat_map(items, &extract_cmd_op_items/1)
  end

  defp extract_cmd_op_items(%{op: :qualified_call} = qc) do
    [subscription_item_label(qc)]
  end

  defp extract_cmd_op_items(%{
         op: :call,
         name: name,
         args: [%{op: :list_literal, items: items}]
       })
       when is_list(items) and is_binary(name) do
    items
    |> Enum.flat_map(&extract_cmd_op_items/1)
    |> then(fn xs -> if xs != [], do: xs, else: [name <> "(…)"] end)
  end

  defp extract_cmd_op_items(%{op: :list_literal, items: items}) when is_list(items) do
    Enum.flat_map(items, &extract_cmd_op_items/1)
  end

  defp extract_cmd_op_items(%{op: :if, then_expr: then_expr, else_expr: else_expr}) do
    extract_cmd_op_items(then_expr) ++ extract_cmd_op_items(else_expr)
  end

  defp extract_cmd_op_items(expr) do
    case subscription_item_label(expr) do
      nil -> []
      s -> [s]
    end
  end

  @spec extract_subscription_calls(Types.ast_expr(), Types.param_list()) :: Types.cmd_call_list()
  def extract_subscription_calls(expr, subscriptions_params),
    do: extract_subscription_calls(expr, %{}, [], subscriptions_params)

  def extract_subscription_calls(
         %{
           op: :qualified_call,
           target: target,
           args: [%{op: :list_literal, items: items}]
         },
         bindings,
         guards,
         subscriptions_params
       )
       when is_binary(target) and is_list(items) and is_map(bindings) and is_list(guards) and
              is_list(subscriptions_params) do
    if subscription_batch_target?(target) do
      Enum.flat_map(items, &extract_subscription_calls(&1, bindings, guards, subscriptions_params))
    else
      subscription_call_rows(target, [%{op: :list_literal, items: items}], bindings, guards)
    end
  end

  def extract_subscription_calls(
         %{
           op: :qualified_call,
           target: target,
           args: args
         },
         bindings,
         guards,
         subscriptions_params
       )
       when is_binary(target) and is_list(args) and is_map(bindings) and is_list(guards) and
              is_list(subscriptions_params) do
    subscription_call_rows(target, args, bindings, guards)
  end

  def extract_subscription_calls(
         %{op: :let_in, name: name, value_expr: value_expr, in_expr: inner},
         bindings,
         guards,
         subscriptions_params
       )
       when is_binary(name) and is_map(bindings) and is_list(guards) and is_list(subscriptions_params) do
    extract_subscription_calls(
      inner,
      Map.put(bindings, name, value_expr),
      guards,
      subscriptions_params
    )
  end

  def extract_subscription_calls(
         %{op: :let_in, in_expr: inner},
         bindings,
         guards,
         subscriptions_params
       )
       when is_map(bindings) and is_list(guards) and is_list(subscriptions_params),
       do: extract_subscription_calls(inner, bindings, guards, subscriptions_params)

  def extract_subscription_calls(
         %{op: :list_literal, items: items},
         bindings,
         guards,
         subscriptions_params
       )
       when is_list(items) and is_map(bindings) and is_list(guards) and is_list(subscriptions_params),
       do: Enum.flat_map(items, &extract_subscription_calls(&1, bindings, guards, subscriptions_params))

  def extract_subscription_calls(
         %{op: :case, subject: subj, branches: branches},
         bindings,
         guards,
         subscriptions_params
       )
       when is_list(branches) and is_map(bindings) and is_list(guards) and is_list(subscriptions_params) do
    allowed = init_case_subjects(subscriptions_params)

    Enum.flat_map(branches, fn
      %{pattern: pattern, expr: expr} ->
        branch_guards =
          if init_case_subject_allowed?(subj, allowed, subscriptions_params, bindings) do
            subject_text = ElmIntrospect.case_subject_text(subj, bindings)
            guards ++ maybe_case_branch_guards(subject_text, pattern)
          else
            guards
          end

        extract_subscription_calls(expr, bindings, branch_guards, subscriptions_params)

      %{expr: expr} ->
        extract_subscription_calls(expr, bindings, guards, subscriptions_params)

      _ ->
        []
    end)
  end

  def extract_subscription_calls(
         %{op: :if, cond: cond, then_expr: then_expr, else_expr: else_expr},
         bindings,
         guards,
         subscriptions_params
       )
       when is_map(bindings) and is_list(guards) and is_list(subscriptions_params) do
    allowed = init_case_subjects(subscriptions_params)

    then_guards =
      guards ++ maybe_if_branch_guards(cond, bindings, allowed, subscriptions_params, :then)

    else_guards =
      guards ++ maybe_if_branch_guards(cond, bindings, allowed, subscriptions_params, :else)

    extract_subscription_calls(then_expr, bindings, then_guards, subscriptions_params) ++
      extract_subscription_calls(else_expr, bindings, else_guards, subscriptions_params)
  end

  def extract_subscription_calls(
         %{op: :if, then_expr: then_expr, else_expr: else_expr},
         bindings,
         guards,
         subscriptions_params
       )
       when is_map(bindings) and is_list(guards) and is_list(subscriptions_params) do
    extract_subscription_calls(then_expr, bindings, guards, subscriptions_params) ++
      extract_subscription_calls(else_expr, bindings, guards, subscriptions_params)
  end

  def extract_subscription_calls(_, _, _, _), do: []

  @spec subscription_call_rows(String.t(), [Types.ast_expr()], Types.binding_map(), [CmdCall.activation_guard()]) ::
          Types.cmd_call_list()
  defp subscription_call_rows(target, args, bindings, guards)
       when is_binary(target) and is_list(args) and is_map(bindings) and is_list(guards) do
    active_guards = Enum.filter(guards, &is_map/1)

    row = %{
      "target" => target,
      "name" => view_type_name(target),
      "event_kind" => subscription_event_kind(target),
      "callback_constructor" => callback_constructor_from_args(args, bindings),
      "label" => subscription_item_label(%{op: :qualified_call, target: target, args: args}),
      "arg_snippets" => Enum.map(args, &subscription_arg_snippet/1),
      "arg_kinds" => Enum.map(args, &expr_arg_kind/1)
    }

    [
      if active_guards == [] do
        row
      else
        Map.put(row, "activation_guards", active_guards)
      end
    ]
  end

  @spec maybe_if_branch_guards(
          Types.ast_expr(),
          Types.binding_map(),
          Types.param_list(),
          Types.param_list(),
          :then | :else
        ) :: [CmdCall.activation_guard()]
  defp maybe_if_branch_guards(cond, bindings, allowed, subscriptions_params, branch)
       when is_map(bindings) and is_list(allowed) and is_list(subscriptions_params) and
              branch in [:then, :else] do
    case guard_from_if_cond(cond, bindings, allowed, subscriptions_params, branch) do
      nil -> []
      guard -> [guard]
    end
  end

  @spec maybe_case_branch_guards(String.t(), Types.ast_expr()) :: [CmdCall.activation_guard()]
  defp maybe_case_branch_guards(subject, pattern) when is_binary(subject) do
    case guard_from_case_branch(subject, pattern) do
      nil -> []
      guard -> [guard]
    end
  end

  @spec guard_from_if_cond(
          Types.ast_expr(),
          Types.binding_map(),
          Types.param_list(),
          Types.param_list(),
          :then | :else
        ) :: CmdCall.activation_guard() | nil
  defp guard_from_if_cond(cond, bindings, allowed, subscriptions_params, branch)
       when is_map(bindings) and is_list(allowed) and is_list(subscriptions_params) and
              branch in [:then, :else] do
    with subject when is_binary(subject) and subject != "" <-
           subscription_guard_subject(cond, bindings),
         true <- init_case_subject_allowed?(subject, allowed, subscriptions_params, bindings) do
      %{
        "kind" => if(branch == :then, do: "field_truthy", else: "field_falsy"),
        "subject" => subject
      }
    else
      _ -> nil
    end
  end

  @spec guard_from_case_branch(String.t(), Types.ast_expr()) :: CmdCall.activation_guard() | nil
  defp guard_from_case_branch(subject, pattern) when is_binary(subject) do
    label = ElmIntrospect.pattern_branch_label(pattern)

    if label in ["?", "_", ""] do
      nil
    else
      %{"kind" => "case_branch", "subject" => subject, "branch" => label}
    end
  end

  @spec subscription_guard_subject(Types.ast_expr(), Types.binding_map()) :: String.t() | nil
  defp subscription_guard_subject(expr, bindings) when is_map(bindings) do
    subject = ElmIntrospect.resolve_case_subject_expr(expr, bindings)
    if subject != "", do: subject, else: nil
  end

  @spec subscription_batch_target?(String.t()) :: boolean()
  defp subscription_batch_target?(target) when is_binary(target) do
    target in ["Sub.batch", "Platform.Sub.batch"] or view_type_name(target) == "batch"
  end

  @spec extract_cmd_calls(Types.ast_expr()) :: Types.cmd_call_list()
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
        "name" => view_type_name(target),
        "callback_constructor" => callback_constructor_from_args(args, bindings),
        "callback_arg_count" => callback_arg_count_from_args(args, bindings),
        "arg_kinds" => Enum.map(args, &expr_arg_kind/1),
        "arg_snippets" => Enum.map(args, &subscription_arg_snippet/1),
        "arg_values" =>
          Enum.map(args, fn arg ->
            arg
            |> inline_let_bindings(bindings, MapSet.new(), 0)
            |> expr_to_json_value(0, 4)
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
        "name" => view_type_name(name),
        "callback_constructor" => callback_constructor_from_args(args, bindings),
        "callback_arg_count" => callback_arg_count_from_args(args, bindings),
        "arg_kinds" => Enum.map(args, &expr_arg_kind/1),
        "arg_snippets" => Enum.map(args, &subscription_arg_snippet/1),
        "arg_values" =>
          Enum.map(args, fn arg ->
            arg
            |> inline_let_bindings(bindings, MapSet.new(), 0)
            |> expr_to_json_value(0, 4)
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
  defp callback_constructor_from_args(args, bindings)
       when is_list(args) and is_map(bindings) do
    args
    |> Enum.reverse()
    |> Enum.find_value(&callback_constructor_from_expr(&1, bindings, MapSet.new(), 0))
  end

  defp callback_constructor_from_args(_, _), do: nil

  @spec callback_arg_count_from_args(list(), Types.binding_map()) :: non_neg_integer()
  defp callback_arg_count_from_args(args, bindings)
       when is_list(args) and is_map(bindings) do
    args
    |> Enum.reverse()
    |> Enum.find_value(&callback_arg_count_from_expr(&1, bindings, MapSet.new(), 0))
    |> case do
      count when is_integer(count) and count >= 0 -> count
      _ -> 0
    end
  end

  defp callback_arg_count_from_args(_, _), do: 0

  @spec callback_arg_count_from_expr(Types.ast_expr(), Types.binding_map(), MapSet.t(String.t()), non_neg_integer()) ::
          non_neg_integer() | nil
  defp callback_arg_count_from_expr(_expr, _bindings, _seen, depth) when depth > 10, do: nil

  defp callback_arg_count_from_expr(
         %{op: :constructor_call, args: args},
         _bindings,
         _seen,
         _depth
       )
       when is_list(args),
       do: length(args)

  defp callback_arg_count_from_expr(%{op: :constructor_call}, _bindings, _seen, _depth), do: 0

  defp callback_arg_count_from_expr(%{op: :var, name: name}, bindings, seen, depth)
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

  defp callback_arg_count_from_expr(_, _, _, _), do: nil

  @spec task_sources_from_args([Types.ast_expr()]) :: [String.t()]
  defp task_sources_from_args(args) when is_list(args) do
    args
    |> Enum.flat_map(&qualified_call_targets/1)
    |> Enum.uniq()
  end

  @spec qualified_call_targets(Types.ast_expr()) :: [String.t()]
  defp qualified_call_targets(%{op: :qualified_call, target: target, args: args})
       when is_binary(target) and is_list(args) do
    [target | Enum.flat_map(args, &qualified_call_targets/1)]
  end

  defp qualified_call_targets(%{op: :call, name: name, args: args})
       when is_binary(name) and is_list(args) do
    [name | Enum.flat_map(args, &qualified_call_targets/1)]
  end

  defp qualified_call_targets(%{op: :constructor_call, args: args}) when is_list(args),
    do: Enum.flat_map(args, &qualified_call_targets/1)

  defp qualified_call_targets(%{op: :lambda, body: body}), do: qualified_call_targets(body)

  defp qualified_call_targets(%{op: :tuple2, left: left, right: right}),
    do: qualified_call_targets(left) ++ qualified_call_targets(right)

  defp qualified_call_targets(%{op: :list_literal, items: items}) when is_list(items),
    do: Enum.flat_map(items, &qualified_call_targets/1)

  defp qualified_call_targets(_), do: []

  @spec callback_preferred_over_result_mapper?(String.t() | nil) :: boolean()
  defp callback_preferred_over_result_mapper?(ctor) when is_binary(ctor) do
    ctor not in ["Current", "Forecast"]
  end

  defp callback_preferred_over_result_mapper?(_ctor), do: false

  @spec callback_constructor_from_expr(Types.ast_expr(), Types.binding_map(), MapSet.t(String.t()), non_neg_integer()) ::
          String.t() | nil
  defp callback_constructor_from_expr(_expr, _bindings, _seen, depth) when depth > 10, do: nil

  defp callback_constructor_from_expr(
         %{op: :constructor_call, target: target},
         _bindings,
         _seen,
         _depth
       )
       when is_binary(target),
       do: view_type_name(target)

  defp callback_constructor_from_expr(%{op: :var, name: name}, bindings, seen, depth)
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

  defp callback_constructor_from_expr(
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

  defp callback_constructor_from_expr(%{op: :qualified_call, args: args}, bindings, seen, depth)
       when is_list(args) do
    Enum.find_value(args, &callback_constructor_from_expr(&1, bindings, seen, depth + 1))
  end

  defp callback_constructor_from_expr(%{op: :call, name: name, args: args}, bindings, seen, depth)
       when is_binary(name) and is_list(args) do
    cond do
      constructor_like_name?(name) and callback_preferred_over_result_mapper?(name) ->
        view_type_name(name)

      true ->
        Enum.find_value(args, &callback_constructor_from_expr(&1, bindings, seen, depth + 1))
    end
  end

  defp callback_constructor_from_expr(%{op: :call, args: args}, bindings, seen, depth)
       when is_list(args) do
    Enum.find_value(args, &callback_constructor_from_expr(&1, bindings, seen, depth + 1))
  end

  defp callback_constructor_from_expr(
         %{op: :let_in, name: name, value_expr: value_expr, in_expr: inner},
         bindings,
         seen,
         depth
       )
       when is_binary(name) and is_map(bindings) do
    next_bindings = Map.put(bindings, name, value_expr)
    callback_constructor_from_expr(inner, next_bindings, seen, depth + 1)
  end

  defp callback_constructor_from_expr(
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

  defp callback_constructor_from_expr(%{op: :list_literal, items: items}, bindings, seen, depth)
       when is_list(items) do
    Enum.find_value(items, &callback_constructor_from_expr(&1, bindings, seen, depth + 1))
  end

  defp callback_constructor_from_expr(_, _bindings, _seen, _depth), do: nil

  @spec constructor_like_name?(String.t()) :: boolean()
  defp constructor_like_name?(name) when is_binary(name) do
    String.match?(name, ~r/^[A-Z][A-Za-z0-9_]*$/)
  end

  @spec expr_arg_kind(Types.ast_expr()) :: String.t()
  defp expr_arg_kind(%{op: op}) when is_atom(op), do: Atom.to_string(op)
  defp expr_arg_kind(_), do: "unknown"

  @spec subscription_item_label(Types.ast_expr()) :: String.t() | nil
  defp subscription_item_label(%{op: :qualified_call, target: "Cmd.none", args: []}),
    do: "Cmd.none"

  defp subscription_item_label(%{op: :qualified_call, target: "Sub.none", args: []}),
    do: "Sub.none"

  defp subscription_item_label(%{op: :qualified_call, target: t, args: args})
       when is_list(args) do
    fnpart = view_type_name(t)

    parts =
      args
      |> Enum.map(&subscription_arg_snippet/1)
      |> Enum.reject(&(&1 == ""))

    if parts == [], do: fnpart, else: fnpart <> "(" <> Enum.join(parts, ", ") <> ")"
  end

  defp subscription_item_label(%{op: :constructor_call, target: t, args: _}) when is_binary(t) do
    view_type_name(t)
  end

  defp subscription_item_label(%{op: :var, name: n}) when is_binary(n), do: n

  defp subscription_item_label(%{op: :cmd_none}), do: "Cmd.none"

  defp subscription_item_label(_), do: nil

  @spec subscription_event_kind(String.t()) :: String.t()
  defp subscription_event_kind(target) when is_binary(target) do
    target
    |> view_type_name()
    |> String.replace(~r/([a-z])([A-Z])/, "\\1 \\2")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
  end

  @spec subscription_arg_snippet(Types.ast_expr()) :: String.t()
  defp subscription_arg_snippet(%{op: :constructor_call, target: t, args: []}) when is_binary(t),
    do: view_type_name(t)

  defp subscription_arg_snippet(%{op: :constructor_call, target: t, args: [_ | _]})
       when is_binary(t),
       do: view_type_name(t) <> "(…)"

  defp subscription_arg_snippet(%{op: :var, name: n}) when is_binary(n), do: n

  defp subscription_arg_snippet(%{op: :int_literal, value: v}), do: Integer.to_string(v)

  defp subscription_arg_snippet(%{op: :string_literal, value: v}) when is_binary(v),
    do: inspect(v)

  defp subscription_arg_snippet(_), do: ""

  @spec init_case_subjects(Types.param_list()) :: Types.param_list()
  defp init_case_subjects(init_params) when is_list(init_params) do
    init_params
    |> Enum.filter(&(is_binary(&1) and &1 != "" and &1 != "_"))
    |> Enum.uniq()
  end

  @spec init_case_subject_allowed?(Types.case_subject(), Types.param_list(), Types.param_list(), Types.binding_map()) ::
          boolean()
  defp init_case_subject_allowed?(subj, allowed, init_params, bindings)
       when is_list(allowed) and is_list(init_params) and is_map(bindings) do
    case ElmIntrospect.case_subject_text(subj, bindings) do
      text when is_binary(text) and text != "" ->
        text in allowed or
          Enum.any?(init_params, fn p ->
            is_binary(p) and p != "_" and p != "" and String.starts_with?(text, p <> ".")
          end)

      _ ->
        false
    end
  end

  @spec scrutinee_case_analysis(Types.ast_expr() | nil, Types.param_list()) :: Types.case_branch_labels()
  def scrutinee_case_analysis(nil, _), do: {[], nil}

  def scrutinee_case_analysis(expr, params) when is_list(params) do
    allowed = init_case_subjects(params)

    {peeled, bindings} = ElmIntrospect.peel_lets_with_bindings(expr)

    case peeled do
      %{op: :case, subject: subj, branches: branches} when is_list(branches) ->
        if init_case_subject_allowed?(subj, allowed, params, bindings) do
          subject_text = ElmIntrospect.case_subject_text(subj, bindings)

          labels =
            Enum.map(branches, fn
              %{pattern: p} -> ElmIntrospect.pattern_branch_label(p)
              _ -> "?"
            end)

          {labels, subject_text}
        else
          {[], nil}
        end

      _ ->
        {[], nil}
    end
  end

  def scrutinee_case_analysis(_, _), do: {[], nil}

  @spec update_case_analysis(Types.ast_expr() | nil, Types.param_list()) :: Types.case_branch_labels()
  def update_case_analysis(nil, _), do: {[], nil}

  def update_case_analysis(expr, update_params) when is_list(update_params) do
    allowed = update_case_subjects(update_params)

    {peeled, bindings} = ElmIntrospect.peel_lets_with_bindings(expr)

    case peeled do
      %{op: :case, subject: subj, branches: branches} when is_list(branches) ->
        if update_case_subject_allowed?(subj, allowed, update_params, bindings) do
          subject_text = ElmIntrospect.case_subject_text(subj, bindings)

          labels =
            Enum.map(branches, fn
              %{pattern: p} -> ElmIntrospect.pattern_branch_label(p)
              _ -> "?"
            end)

          {labels, subject_text}
        else
          {[], nil}
        end

      _ ->
        {[], nil}
    end
  end

  def update_case_analysis(_, _), do: {[], nil}

  @spec update_case_subject_allowed?(Types.case_subject(), Types.param_list(), Types.param_list(), Types.binding_map()) ::
          boolean()
  defp update_case_subject_allowed?(subj, allowed, update_params, bindings)
       when is_list(allowed) and is_list(update_params) and is_map(bindings) do
    case ElmIntrospect.case_subject_text(subj, bindings) do
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
  defp update_case_subjects(update_params) when is_list(update_params) do
    base = ["msg", "message"]

    case List.first(update_params) do
      first when is_binary(first) and first != "" and first != "_" ->
        Enum.uniq([first | base])

      _ ->
        base
    end
  end
  @spec init_model_expr(Types.ast_expr() | nil) :: Types.ast_expr() | nil
  defp init_model_expr(expr) do
    expr
    |> peel_lets()
    |> case do
      %{op: :tuple2, left: left} ->
        left

      %{op: :case, branches: branches} = case_expr when is_list(branches) ->
        case first_case_branch_init_model(branches) do
          nil -> case_expr
          left -> left
        end

      other ->
        other
    end
  end

  @spec first_case_branch_init_model([Types.ast_expr()]) :: Types.ast_expr() | nil
  defp first_case_branch_init_model(branches) when is_list(branches) do
    Enum.find_value(branches, fn
      %{expr: e} ->
        case peel_lets(e) do
          %{op: :tuple2, left: left} -> left
          _ -> nil
        end

      _ ->
        nil
    end)
  end

  @spec peel_lets(Types.ast_expr()) :: Types.ast_expr()
  defp peel_lets(%{op: :let_in, in_expr: inner}), do: peel_lets(inner)
  defp peel_lets(other), do: other
  @spec inline_let_bindings(Types.ast_expr(), Types.binding_map(), MapSet.t(), non_neg_integer()) ::
          Types.ast_expr()
  defp inline_let_bindings(expr, _bindings, _seen, depth) when depth > 12, do: expr

  defp inline_let_bindings(%{op: :var, name: name}, bindings, seen, depth)
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

  defp inline_let_bindings(%{op: :constructor_call} = expr, bindings, seen, depth) do
    Map.update!(expr, :args, fn args ->
      Enum.map(args, &inline_let_bindings(&1, bindings, seen, depth + 1))
    end)
  end

  defp inline_let_bindings(%{op: :qualified_call} = expr, bindings, seen, depth) do
    Map.update!(expr, :args, fn args ->
      Enum.map(args, &inline_let_bindings(&1, bindings, seen, depth + 1))
    end)
  end

  defp inline_let_bindings(%{op: :call} = expr, bindings, seen, depth) do
    Map.update!(expr, :args, fn args ->
      Enum.map(args, &inline_let_bindings(&1, bindings, seen, depth + 1))
    end)
  end

  defp inline_let_bindings(%{op: :field_access, arg: arg} = expr, bindings, seen, depth) do
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

  defp inline_let_bindings(%{op: :list_literal} = expr, bindings, seen, depth) do
    Map.update!(expr, :items, fn xs ->
      Enum.map(xs, &inline_let_bindings(&1, bindings, seen, depth + 1))
    end)
  end

  defp inline_let_bindings(%{op: :tuple2, left: left, right: right}, bindings, seen, depth) do
    %{
      op: :tuple2,
      left: inline_let_bindings(left, bindings, seen, depth + 1),
      right: inline_let_bindings(right, bindings, seen, depth + 1)
    }
  end

  defp inline_let_bindings(expr, _bindings, _seen, _depth), do: expr

  @spec expr_to_json_value(Types.ast_expr(), non_neg_integer(), non_neg_integer(), Types.module_ref() | nil) ::
          Types.json_value()
  defp expr_to_json_value(expr, depth, max, mod \\ nil)

  defp expr_to_json_value(%{op: :record_literal, fields: fields}, depth, max, mod) when depth < max do
    Enum.into(fields, %{}, fn %{name: n, expr: e} ->
      {n, expr_to_json_value(e, depth + 1, max, mod)}
    end)
  end

  defp expr_to_json_value(%{op: :int_literal, value: v}, _, _, _), do: v

  defp expr_to_json_value(%{op: :string_literal, value: v}, _, _, _), do: v

  defp expr_to_json_value(%{op: :char_literal, value: v}, _, _, _), do: v

  defp expr_to_json_value(%{op: :constructor_call, target: t, args: args}, depth, max, mod)
       when depth < max do
    %{
      "$ctor" => t,
      "$args" => Enum.map(args, &expr_to_json_value(&1, depth + 1, max, mod))
    }
  end

  defp expr_to_json_value(%{op: :qualified_call, target: t, args: args}, depth, max, mod)
       when depth < max do
    %{"$call" => t, "$args" => Enum.map(args, &expr_to_json_value(&1, depth + 1, max, mod))}
  end

  defp expr_to_json_value(%{op: :call, name: name, args: args}, depth, max, mod)
       when is_binary(name) and depth < max do
    %{"$call" => name, "$args" => Enum.map(args, &expr_to_json_value(&1, depth + 1, max, mod))}
  end

  defp expr_to_json_value(%{op: :var, name: n}, depth, max, %Module{} = mod) do
    case ElmIntrospect.find_function_definition(mod, n) do
      %{expr: expr} when is_map(expr) -> expr_to_json_value(expr, depth, max, mod)
      _ -> %{"$var" => n}
    end
  end

  defp expr_to_json_value(%{op: :var, name: n}, _, _, _), do: %{"$var" => n}

  defp expr_to_json_value(%{op: :field_access, arg: arg, field: field}, depth, max, mod)
       when is_binary(field) and depth < max do
    on_expr =
      cond do
        is_binary(arg) -> %{"$var" => arg}
        is_map(arg) -> expr_to_json_value(arg, depth + 1, max, mod)
        true -> %{"$opaque" => true}
      end

    %{"$field" => field, "$on" => on_expr}
  end

  defp expr_to_json_value(%{op: :cmd_none}, _, _, _), do: %{"$ctor" => "Cmd.none", "$args" => []}

  defp expr_to_json_value(%{op: :list_literal, items: items}, depth, max, mod) when depth < max do
    Enum.map(items, &expr_to_json_value(&1, depth + 1, max, mod))
  end

  defp expr_to_json_value(%{op: :tuple2, left: l, right: r}, depth, max, mod) when depth < max do
    [expr_to_json_value(l, depth + 1, max, mod), expr_to_json_value(r, depth + 1, max, mod)]
  end

  defp expr_to_json_value(%{op: :unsupported, source: s}, _, _, _) when is_binary(s) do
    %{"$opaque" => true, "preview" => String.slice(s, 0, 120)}
  end

  defp expr_to_json_value(%{op: op}, _, _, _), do: %{"$opaque" => true, "op" => to_string(op)}

  defp expr_to_json_value(_, _, _, _), do: %{"$opaque" => true}

  @spec peel_update_outer(Types.ast_expr()) :: Types.ast_expr()
  defp peel_update_outer(%{op: :let_in, in_expr: inner}), do: peel_update_outer(inner)
  defp peel_update_outer(other), do: other

  @spec pattern_constructor_name(Types.ast_expr()) :: String.t() | nil
  defp pattern_constructor_name(%{kind: :constructor, name: n}) when is_binary(n), do: n
  defp pattern_constructor_name(_), do: nil

  @spec init_model_value(Types.ast_expr() | nil, Types.module_ref()) :: Types.json_value() | nil
  def init_model_value(nil, _mod), do: nil

  def init_model_value(expr, mod) do
    expr
    |> init_model_expr()
    |> expr_to_json_value(0, 12, mod)
  end

  @spec function_cmd_calls(Types.module_ref()) :: Types.function_cmd_calls_map()
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
