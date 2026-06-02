defmodule ElmEx.DebuggerContract.EffectAnalysis.Subscriptions do
  @moduledoc false

  alias ElmEx.Frontend.Module
  alias ElmEx.DebuggerContract.Types

  alias ElmEx.DebuggerContract.EffectAnalysis.CmdCalls
  alias ElmEx.DebuggerContract.EffectAnalysis.Support
  alias ElmEx.DebuggerContract.CmdCall

  def subscriptions_outline(nil, _), do: []

  def subscriptions_outline(expr, subscriptions_params) when is_list(subscriptions_params) do
    allowed = Support.init_case_subjects(subscriptions_params)
    {peeled, bindings} = ElmEx.DebuggerContract.peel_lets_with_bindings(expr)

    case peeled do
      %{op: :case, subject: subj, branches: branches} when is_list(branches) ->
        if Support.init_case_subject_allowed?(subj, allowed, subscriptions_params, bindings) do
          Enum.flat_map(branches, fn
            %{expr: e} -> e |> Support.peel_lets() |> extract_subscription_items()
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
  def extract_subscription_items(%{
        op: :qualified_call,
        args: [%{op: :list_literal, items: items}]
      })
      when is_list(items) do
    items |> Enum.flat_map(&extract_subscription_items/1) |> Enum.uniq()
  end

  def extract_subscription_items(%{op: :qualified_call} = qc) do
    [subscription_item_label(qc)]
  end

  def extract_subscription_items(%{
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

  def extract_subscription_items(%{op: :list_literal, items: items}) when is_list(items) do
    items |> Enum.flat_map(&extract_subscription_items/1) |> Enum.uniq()
  end

  def extract_subscription_items(%{op: :call, args: args}) when is_list(args) do
    args |> Enum.flat_map(&extract_subscription_items/1) |> Enum.uniq()
  end

  def extract_subscription_items(%{op: :if, then_expr: then_expr, else_expr: else_expr}) do
    (extract_subscription_items(then_expr) ++ extract_subscription_items(else_expr))
    |> Enum.uniq()
  end

  def extract_subscription_items(expr) do
    case subscription_item_label(expr) do
      nil -> []
      s -> [s]
    end
  end

  @spec extract_subscription_calls(Types.ast_expr(), Types.param_list(), Module.t() | nil) ::
          Types.cmd_call_list()
  def extract_subscription_calls(expr, subscriptions_params, mod \\ nil),
    do: extract_subscription_calls(expr, %{}, [], subscriptions_params, mod)

  def extract_subscription_calls(
        %{
          op: :qualified_call,
          target: target,
          args: [%{op: :list_literal, items: items}]
        },
        bindings,
        guards,
        subscriptions_params,
        mod
      )
      when is_binary(target) and is_list(items) and is_map(bindings) and is_list(guards) and
             is_list(subscriptions_params) do
    if subscription_batch_target?(target) do
      Enum.flat_map(
        items,
        &extract_subscription_calls(&1, bindings, guards, subscriptions_params, mod)
      )
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
        subscriptions_params,
        _mod
      )
      when is_binary(target) and is_list(args) and is_map(bindings) and is_list(guards) and
             is_list(subscriptions_params) do
    subscription_call_rows(target, args, bindings, guards)
  end

  def extract_subscription_calls(
        %{op: :let_in, name: name, value_expr: value_expr, in_expr: inner},
        bindings,
        guards,
        subscriptions_params,
        mod
      )
      when is_binary(name) and is_map(bindings) and is_list(guards) and
             is_list(subscriptions_params) do
    extract_subscription_calls(
      inner,
      Map.put(bindings, name, value_expr),
      guards,
      subscriptions_params,
      mod
    )
  end

  def extract_subscription_calls(
        %{op: :let_in, in_expr: inner},
        bindings,
        guards,
        subscriptions_params,
        mod
      )
      when is_map(bindings) and is_list(guards) and is_list(subscriptions_params),
      do: extract_subscription_calls(inner, bindings, guards, subscriptions_params, mod)

  def extract_subscription_calls(
        %{op: :list_literal, items: items},
        bindings,
        guards,
        subscriptions_params,
        mod
      )
      when is_list(items) and is_map(bindings) and is_list(guards) and
             is_list(subscriptions_params),
      do:
        Enum.flat_map(
          items,
          &extract_subscription_calls(&1, bindings, guards, subscriptions_params, mod)
        )

  def extract_subscription_calls(
        %{op: :case, subject: subj, branches: branches},
        bindings,
        guards,
        subscriptions_params,
        mod
      )
      when is_list(branches) and is_map(bindings) and is_list(guards) and
             is_list(subscriptions_params) do
    allowed = Support.init_case_subjects(subscriptions_params)

    Enum.flat_map(branches, fn
      %{pattern: pattern, expr: expr} ->
        branch_guards =
          if Support.init_case_subject_allowed?(subj, allowed, subscriptions_params, bindings) do
            subject_text = ElmEx.DebuggerContract.case_subject_text(subj, bindings)
            guards ++ maybe_case_branch_guards(subject_text, pattern)
          else
            guards
          end

        extract_subscription_calls(expr, bindings, branch_guards, subscriptions_params, mod)

      %{expr: expr} ->
        extract_subscription_calls(expr, bindings, guards, subscriptions_params, mod)

      _ ->
        []
    end)
  end

  def extract_subscription_calls(
        %{op: :if, cond: cond, then_expr: then_expr, else_expr: else_expr},
        bindings,
        guards,
        subscriptions_params,
        mod
      )
      when is_map(bindings) and is_list(guards) and is_list(subscriptions_params) do
    allowed = Support.init_case_subjects(subscriptions_params)

    then_guards =
      guards ++ maybe_if_branch_guards(cond, bindings, allowed, subscriptions_params, :then)

    else_guards =
      guards ++ maybe_if_branch_guards(cond, bindings, allowed, subscriptions_params, :else)

    extract_subscription_calls(then_expr, bindings, then_guards, subscriptions_params, mod) ++
      extract_subscription_calls(else_expr, bindings, else_guards, subscriptions_params, mod)
  end

  def extract_subscription_calls(
        %{op: :if, then_expr: then_expr, else_expr: else_expr},
        bindings,
        guards,
        subscriptions_params,
        mod
      )
      when is_map(bindings) and is_list(guards) and is_list(subscriptions_params) do
    extract_subscription_calls(then_expr, bindings, guards, subscriptions_params, mod) ++
      extract_subscription_calls(else_expr, bindings, guards, subscriptions_params, mod)
  end

  def extract_subscription_calls(
        %{op: :call, name: name, args: args},
        bindings,
        guards,
        subscriptions_params,
        mod
      )
      when is_binary(name) and is_list(args) and is_map(bindings) and is_list(guards) and
             is_list(subscriptions_params) do
    from_args =
      Enum.flat_map(
        args,
        &extract_subscription_calls(&1, bindings, guards, subscriptions_params, mod)
      )

    from_body =
      subscription_calls_from_local_helper(
        mod,
        name,
        args,
        bindings,
        guards,
        subscriptions_params
      )

    from_args ++ from_body
  end

  def extract_subscription_calls(
        %{op: :call, args: args},
        bindings,
        guards,
        subscriptions_params,
        mod
      )
      when is_list(args) and is_map(bindings) and is_list(guards) and
             is_list(subscriptions_params) do
    Enum.flat_map(
      args,
      &extract_subscription_calls(&1, bindings, guards, subscriptions_params, mod)
    )
  end

  def extract_subscription_calls(_, _, _, _, _), do: []

  @spec subscription_calls_from_local_helper(
          Module.t() | nil,
          String.t(),
          list(),
          Types.binding_map(),
          list(),
          Types.param_list()
        ) :: Types.cmd_call_list()
  defp subscription_calls_from_local_helper(
         %Module{} = mod,
         name,
         args,
         bindings,
         guards,
         subscriptions_params
       )
       when is_binary(name) and is_list(args) and is_map(bindings) and is_list(guards) and
              is_list(subscriptions_params) do
    case ElmEx.DebuggerContract.find_function_definition(mod, name) do
      %{expr: body, args: param_names} when is_map(body) ->
        body_bindings = call_param_bindings(param_names, args, bindings)

        extract_subscription_calls(body, body_bindings, guards, subscriptions_params, mod)

      _ ->
        []
    end
  end

  defp subscription_calls_from_local_helper(
         _mod,
         _name,
         _args,
         _bindings,
         _guards,
         _subscriptions_params
       ),
       do: []

  @spec call_param_bindings([String.t()], list(), Types.binding_map()) :: Types.binding_map()
  defp call_param_bindings(param_names, args, bindings)
       when is_list(param_names) and is_list(args) and is_map(bindings) do
    param_names
    |> Enum.zip(args)
    |> Enum.reduce(bindings, fn
      {param, arg_expr}, acc when is_binary(param) and param != "" ->
        Map.put(acc, param, arg_expr)

      _, acc ->
        acc
    end)
  end

  defp call_param_bindings(_param_names, _args, bindings), do: bindings

  def subscription_call_rows(target, args, bindings, guards)
      when is_binary(target) and is_list(args) and is_map(bindings) and is_list(guards) do
    active_guards = Enum.filter(guards, &is_map/1)

    row = %{
      "target" => target,
      "name" => Support.view_type_name(target),
      "event_kind" => subscription_event_kind(target),
      "callback_constructor" => CmdCalls.callback_constructor_from_args(args, bindings),
      "label" => subscription_item_label(%{op: :qualified_call, target: target, args: args}),
      "arg_snippets" => Enum.map(args, &subscription_arg_snippet/1),
      "arg_kinds" => Enum.map(args, &CmdCalls.expr_arg_kind/1)
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
  def maybe_if_branch_guards(cond, bindings, allowed, subscriptions_params, branch)
      when is_map(bindings) and is_list(allowed) and is_list(subscriptions_params) and
             branch in [:then, :else] do
    case guard_from_if_cond(cond, bindings, allowed, subscriptions_params, branch) do
      nil -> []
      guard -> [guard]
    end
  end

  @spec maybe_case_branch_guards(String.t(), Types.ast_expr()) :: [CmdCall.activation_guard()]
  def maybe_case_branch_guards(subject, pattern) when is_binary(subject) do
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
  def guard_from_if_cond(cond, bindings, allowed, subscriptions_params, branch)
      when is_map(bindings) and is_list(allowed) and is_list(subscriptions_params) and
             branch in [:then, :else] do
    with subject when is_binary(subject) and subject != "" <-
           subscription_guard_subject(cond, bindings),
         true <-
           Support.init_case_subject_allowed?(subject, allowed, subscriptions_params, bindings) do
      %{
        "kind" => if(branch == :then, do: "field_truthy", else: "field_falsy"),
        "subject" => subject
      }
    else
      _ -> nil
    end
  end

  @spec guard_from_case_branch(String.t(), Types.ast_expr()) :: CmdCall.activation_guard() | nil
  def guard_from_case_branch(subject, pattern) when is_binary(subject) do
    label = ElmEx.DebuggerContract.pattern_branch_label(pattern)

    if label in ["?", "_", ""] do
      nil
    else
      %{"kind" => "case_branch", "subject" => subject, "branch" => label}
    end
  end

  @spec subscription_guard_subject(Types.ast_expr(), Types.binding_map()) :: String.t() | nil
  def subscription_guard_subject(expr, bindings) when is_map(bindings) do
    subject = ElmEx.DebuggerContract.resolve_case_subject_expr(expr, bindings)
    if subject != "", do: subject, else: nil
  end

  @spec subscription_batch_target?(String.t()) :: boolean()
  def subscription_batch_target?(target) when is_binary(target) do
    target in ["Sub.batch", "Platform.Sub.batch"] or Support.view_type_name(target) == "batch"
  end

  def subscription_item_label(%{op: :qualified_call, target: "Cmd.none", args: []}),
    do: "Cmd.none"

  def subscription_item_label(%{op: :qualified_call, target: "Sub.none", args: []}),
    do: "Sub.none"

  def subscription_item_label(%{op: :qualified_call, target: t, args: args})
      when is_list(args) do
    fnpart = Support.view_type_name(t)

    parts =
      args
      |> Enum.map(&subscription_arg_snippet/1)
      |> Enum.reject(&(&1 == ""))

    if parts == [], do: fnpart, else: fnpart <> "(" <> Enum.join(parts, ", ") <> ")"
  end

  def subscription_item_label(%{op: :constructor_call, target: t, args: _}) when is_binary(t) do
    Support.view_type_name(t)
  end

  def subscription_item_label(%{op: :var, name: n}) when is_binary(n), do: n

  def subscription_item_label(%{op: :cmd_none}), do: "Cmd.none"

  def subscription_item_label(_), do: nil

  @spec subscription_event_kind(String.t()) :: String.t()
  def subscription_event_kind(target) when is_binary(target) do
    target
    |> Support.view_type_name()
    |> String.replace(~r/([a-z])([A-Z])/, "\\1 \\2")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
  end

  @spec subscription_arg_snippet(Types.ast_expr()) :: String.t()
  def subscription_arg_snippet(%{op: :constructor_call, target: t, args: []}) when is_binary(t),
    do: Support.view_type_name(t)

  def subscription_arg_snippet(%{op: :constructor_call, target: t, args: [_ | _]})
      when is_binary(t),
      do: Support.view_type_name(t) <> "(…)"

  def subscription_arg_snippet(%{op: :var, name: n}) when is_binary(n), do: n

  def subscription_arg_snippet(%{op: :int_literal, value: v}), do: Integer.to_string(v)

  def subscription_arg_snippet(%{op: :string_literal, value: v}) when is_binary(v),
    do: inspect(v)

  def subscription_arg_snippet(_), do: ""
end
