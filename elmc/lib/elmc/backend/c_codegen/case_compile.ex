defmodule Elmc.Backend.CCodegen.CaseCompile do
  @moduledoc false

  alias Elmc.Backend.CCodegen.ConstructorTagCase
  alias Elmc.Backend.CCodegen.HelperParams
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Native.Int, as: NativeInt
  alias Elmc.Backend.CCodegen.Native.IntCase, as: NativeIntCase
  alias Elmc.Backend.CCodegen.Patterns
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util

  @spec dispatch(
          Types.case_subject(),
          Types.case_branches(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  @spec dispatch(Types.ir_case_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  def dispatch(%{op: :case, subject: subject, branches: branches}, env, counter),
    do: dispatch(subject, branches, env, counter)

  def dispatch(subject, branches, env, counter) do
    subject_expr = subject_expr(subject)

    cond do
      NativeInt.expr?(subject_expr, env) and NativeIntCase.branches?(branches) ->
        NativeIntCase.compile(subject_expr, branches, env, counter)

      ConstructorTagCase.switch_eligible?(branches) and
          ConstructorTagCase.native_subject_switch?(subject_expr, branches, env) ->
        ConstructorTagCase.compile_native_subject(subject_expr, branches, env, counter)

      ConstructorTagCase.switch_eligible?(branches) ->
        ConstructorTagCase.compile(subject, branches, env, counter)

      true ->
        compile_boxed(subject, branches, env, counter)
    end
  end

  @spec subject_expr(Types.case_subject()) :: Types.ir_expr()
  def subject_expr(subject) when is_binary(subject), do: %{op: :var, name: subject}
  def subject_expr(subject), do: subject

  @spec branch_assignment(
          Types.ir_expr(),
          String.t(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: {String.t(), String.t(), Types.compile_counter()}
  def branch_assignment(%{op: :string_literal, value: value}, out, _env, counter) do
    {"", "#{out} = elmc_new_string(\"#{Util.escape_c_string(value)}\");", counter}
  end

  def branch_assignment(%{op: :int_literal, value: 0}, out, _env, counter) do
    {"", "#{out} = elmc_int_zero();", counter}
  end

  def branch_assignment(%{op: :int_literal, value: value}, out, _env, counter)
      when is_integer(value) do
    {"", "#{out} = elmc_new_int(#{value});", counter}
  end

  def branch_assignment(expr, out, env, counter) do
    {expr_code, expr_var, counter} = Host.compile_expr(expr, env, counter)
    {expr_code, "#{out} = #{expr_var};", counter}
  end

  @spec compile_boxed(
          Types.case_subject(),
          Types.case_branches(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  def compile_boxed(subject, branches, env, counter) do
    {subject_setup, subject_ref, counter} =
      ConstructorTagCase.compile_subject_ref(subject, env, counter)

    case_env =
      if Patterns.maybe_unwrap_just_case?(branches),
        do: Map.put(env, :maybe_unwrap_just, true),
        else: env

    next = counter + 1
    out = "tmp_#{next}"

    {branch_code, final_counter} =
      branches
      |> Enum.with_index()
      |> Enum.reduce_while({"", next}, fn {branch, branch_index}, {acc, c} ->
        last_branch? = branch_index == length(branches) - 1

        {branch_env, unwrap_setup, unwrap_release, c} =
          Patterns.maybe_unwrap_var_branch(case_env, branch, subject_ref, c)

        {expr_code, assignment_code, c2} =
          branch_assignment(branch.expr, out, branch_env, c)

        cond_code = Patterns.pattern_condition(subject_ref, branch.pattern)

        enter_probe =
          env |> battery_alert_case_probe(branch_index, :enter) |> Host.agent_probe_region()

        after_expr_probe =
          env |> battery_alert_case_probe(branch_index, :after_expr) |> Host.agent_probe_region()

        branch_body =
          maybe_extract_branch_helper(
            branch,
            branch_env,
            subject_ref,
            out,
            enter_probe,
            unwrap_setup,
            expr_code,
            after_expr_probe,
            assignment_code,
            unwrap_release
          )

        cond do
          cond_code == "0" ->
            {:cont, {acc, c2}}

          cond_code == "1" and acc == "" ->
            {:halt, {acc <> branch_body, c2}}

          last_branch? and acc == "" ->
            {:halt, {acc <> branch_body, c2}}

          cond_code == "1" ->
            {:halt, {acc <> else_branch_snippet(branch_body), c2}}

          last_branch? and acc != "" ->
            {:halt, {acc <> else_branch_snippet(branch_body), c2}}

          true ->
            {:cont, {acc <> if_branch_snippet(cond_code, branch_body, acc == ""), c2}}
        end
      end)

    after_setup_probe =
      env |> battery_alert_case_probe(:case, :after_setup) |> Host.agent_probe_region()

    after_branches_probe =
      env |> battery_alert_case_probe(:case, :after_branches) |> Host.agent_probe_region()

    code =
      Enum.join(
        [
          subject_setup,
          "ElmcValue *#{out};",
          after_setup_probe,
          branch_code,
          after_branches_probe
        ],
        "\n"
      )

    {code, out, final_counter}
  end

  defp if_branch_snippet(cond_code, branch_body, first_branch?) do
    keyword = if first_branch?, do: "if", else: "else if"
    prefix = if first_branch?, do: "", else: "} "

    """
    #{prefix}#{keyword} (#{cond_code}) {
    #{format_branch_body(branch_body)}

    """
  end

  defp else_branch_snippet(branch_body) do
    """
    } else {
    #{format_branch_body(branch_body)}
    }
    """
  end

  defp format_branch_body(body) do
    Util.format_c_block(body, 4)
  end

  defp maybe_extract_branch_helper(
         branch,
         branch_env,
         subject_ref,
         out,
         enter_probe,
         unwrap_setup,
         expr_code,
         after_expr_probe,
         assignment_code,
         unwrap_release
       ) do
    inline_body =
      format_branch_body(
        Enum.join(
          [enter_probe, unwrap_setup, expr_code, after_expr_probe, assignment_code, unwrap_release],
          "\n"
        )
      )

    if extract_branch_helper?(inline_body) do
      case branch_helper_params(branch, branch_env, subject_ref) do
        {:ok, params} when params != [] ->
          helper_id = Process.get(:elmc_generic_helper_counter, 0) + 1
          Process.put(:elmc_generic_helper_counter, helper_id)

          helper_name =
            "elmc_case_branch_helper_#{Util.safe_c_suffix(Map.get(branch_env, :__module__, "Main"))}_#{Util.safe_c_suffix(Map.get(branch_env, :__function_name__, "fn"))}_#{helper_id}"

          helper_out = "branch_out"
          helper_assignment = String.replace(assignment_code, "#{out} =", "#{helper_out} =")

          helper_param_decls = HelperParams.param_decls(params)

          helper_def = """
          static ElmcValue *#{helper_name}(#{helper_param_decls}) {
            ElmcValue *#{helper_out} = NULL;
          #{Util.indent(enter_probe, 2)}
          #{Util.indent(unwrap_setup, 2)}
          #{Util.indent(expr_code, 2)}
          #{Util.indent(after_expr_probe, 2)}
            #{helper_assignment}
          #{Util.indent(unwrap_release, 2)}
            return #{helper_out};
          }
          """

          Process.put(
            :elmc_generic_helper_defs,
            [helper_def | Process.get(:elmc_generic_helper_defs, [])]
          )

          call_args = HelperParams.call_args(params)

          """
              #{out} = #{helper_name}(#{call_args});
          """

        _ ->
          inline_body
      end
    else
      inline_body
    end
  end

  defp extract_branch_helper?(body) do
    Process.get(:elmc_generic_helper_defs) != nil and emitted_line_count(body) >= 60
  end

  defp emitted_line_count(code), do: code |> String.split("\n") |> length()

  defp branch_helper_params(branch, branch_env, subject_ref) do
    excluded =
      case branch.pattern do
        %{kind: :var, name: name} when is_binary(name) -> MapSet.new([name])
        _ -> MapSet.new()
      end

    vars =
      branch.expr
      |> external_vars()
      |> MapSet.to_list()
      |> Enum.reject(&MapSet.member?(excluded, &1))
      |> Enum.sort()

    case HelperParams.collect(vars, branch_env) do
      :error ->
        :error

      {:ok, params} ->
        params =
          params
          |> maybe_add_subject_param(subject_ref)
          |> Enum.uniq_by(fn {_var, spec} -> spec end)

        {:ok, params}
    end
  end

  defp maybe_add_subject_param(params, subject_ref) when is_binary(subject_ref) do
    if Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_]*$/, subject_ref) do
      [{:__case_subject__, {:boxed, subject_ref}} | params]
    else
      params
    end
  end

  defp external_vars(expr), do: external_vars(expr, MapSet.new())

  defp external_vars(%{op: :var, name: name}, bound) when is_binary(name) do
    if MapSet.member?(bound, name), do: MapSet.new(), else: MapSet.new([name])
  end

  defp external_vars(%{op: :let_in, name: name, value_expr: value_expr, in_expr: in_expr}, bound) do
    value_vars = external_vars(value_expr, bound)
    in_vars = external_vars(in_expr, MapSet.put(bound, name))
    MapSet.union(value_vars, in_vars)
  end

  defp external_vars(%{op: :lambda, args: args, body: body}, bound) when is_list(args) do
    lambda_bound = Enum.reduce(args, bound, &MapSet.put(&2, &1))
    external_vars(body, lambda_bound)
  end

  defp external_vars(%{op: :field_access, arg: arg}, bound) when is_binary(arg) do
    if MapSet.member?(bound, arg), do: MapSet.new(), else: MapSet.new([arg])
  end

  defp external_vars(expr, bound) when is_map(expr) do
    Enum.reduce(expr, MapSet.new(), fn
      {_key, value}, acc when is_map(value) or is_list(value) ->
        MapSet.union(acc, external_vars(value, bound))

      {_key, _value}, acc ->
        acc
    end)
  end

  defp external_vars(values, bound) when is_list(values) do
    Enum.reduce(values, MapSet.new(), fn value, acc ->
      MapSet.union(acc, external_vars(value, bound))
    end)
  end

  defp external_vars(_expr, _bound), do: MapSet.new()

  @spec battery_alert_case_probe(Types.compile_env(), term(), atom()) :: String.t()
  defp battery_alert_case_probe(_env, _branch_index, _position), do: ""
end
