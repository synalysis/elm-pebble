defmodule Ide.Debugger.ElmIntrospect.EffectAnalysis do
  @moduledoc false
  alias Ide.Debugger.ElmIntrospect
  alias Ide.Debugger.ElmIntrospect.Types

  alias Ide.Debugger.ElmIntrospect.EffectAnalysis.CmdCalls
  alias Ide.Debugger.ElmIntrospect.EffectAnalysis.Subscriptions
  alias Ide.Debugger.ElmIntrospect.EffectAnalysis.Support
  alias Ide.Debugger.ElmIntrospect.Types

  def main_program_outline(nil), do: nil

  def main_program_outline(expr) do
    expr
    |> Support.peel_lets()
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
  def main_kind_from_target(t) when is_binary(t) do
    case Support.view_type_name(t) do
      "worker" -> "worker"
      "element" -> "element"
      "document" -> "document"
      "sandbox" -> "sandbox"
      _ -> "unknown"
    end
  end
  def scrutinee_case_analysis(nil, _), do: {[], nil}

  def scrutinee_case_analysis(expr, params) when is_list(params) do
    allowed = Support.init_case_subjects(params)

    {peeled, bindings} = ElmIntrospect.peel_lets_with_bindings(expr)

    case peeled do
      %{op: :case, subject: subj, branches: branches} when is_list(branches) ->
        if Support.init_case_subject_allowed?(subj, allowed, params, bindings) do
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
    allowed = Support.update_case_subjects(update_params)

    {peeled, bindings} = ElmIntrospect.peel_lets_with_bindings(expr)

    case peeled do
      %{op: :case, subject: subj, branches: branches} when is_list(branches) ->
        if Support.update_case_subject_allowed?(subj, allowed, update_params, bindings) do
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
  @spec init_model_expr(Types.ast_expr() | nil) :: Types.ast_expr() | nil
  def init_model_expr(expr) do
    expr
    |> Support.peel_lets()
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
  def first_case_branch_init_model(branches) when is_list(branches) do
    Enum.find_value(branches, fn
      %{expr: e} ->
        case Support.peel_lets(e) do
          %{op: :tuple2, left: left} -> left
          _ -> nil
        end

      _ ->
        nil
    end)
  end


  @spec init_model_value(Types.ast_expr() | nil, Types.module_ref()) :: Types.json_value() | nil
  def init_model_value(nil, _mod), do: nil

  def init_model_value(expr, mod) do
    expr
    |> init_model_expr()
    |> Support.expr_to_json_value(0, 12, mod)
  end

  @spec function_cmd_calls(Types.module_ref()) :: Types.function_cmd_calls_map()

  defdelegate function_cmd_calls(mod), to: CmdCalls
  defdelegate init_cmd_ops_outline(expr, init_params), to: CmdCalls
  defdelegate init_cmd_calls_outline(expr, init_params), to: CmdCalls
  defdelegate update_cmd_ops_outline(expr, update_params), to: CmdCalls
  defdelegate update_cmd_calls_outline(expr, update_params), to: CmdCalls
  defdelegate subscriptions_outline(expr, subscriptions_params), to: Subscriptions
  defdelegate extract_subscription_calls(expr, subscriptions_params), to: Subscriptions

  defdelegate extract_subscription_calls(expr, bindings, guards, subscriptions_params),
              to: Subscriptions
end
