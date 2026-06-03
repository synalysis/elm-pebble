defmodule Elmc.Backend.CCodegen.CaseCompile do
  @moduledoc false

  alias Elmc.Backend.CCodegen.ConstructorTagCase
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

    next = counter + 1
    out = "tmp_#{next}"

    {branch_code, final_counter} =
      branches
      |> Enum.with_index()
      |> Enum.reduce_while({"", next}, fn {branch, branch_index}, {acc, c} ->
        last_branch? = branch_index == length(branches) - 1
        branch_env = Patterns.bind_pattern(env, branch.pattern, subject_ref)

        {expr_code, assignment_code, c2} =
          branch_assignment(branch.expr, out, branch_env, c)

        cond_code = Patterns.pattern_condition(subject_ref, branch.pattern)

        enter_probe =
          env |> battery_alert_case_probe(branch_index, :enter) |> Host.agent_probe_region()

        after_expr_probe =
          env |> battery_alert_case_probe(branch_index, :after_expr) |> Host.agent_probe_region()

        branch_body = """
        #{Util.indent(enter_probe, 4)}
        #{Util.indent(expr_code, 4)}
        #{Util.indent(after_expr_probe, 4)}
            #{assignment_code}
        """

        cond do
          cond_code == "0" ->
            {:cont, {acc, c2}}

          cond_code == "1" and acc == "" ->
            {:halt, {acc <> branch_body, c2}}

          last_branch? and acc == "" ->
            {:halt, {acc <> branch_body, c2}}

          cond_code == "1" ->
            snippet = """
            else {
            #{branch_body}
            }
            """

            {:halt, {acc <> snippet, c2}}

          last_branch? and acc != "" ->
            snippet = """
            else {
            #{branch_body}
            }
            """

            {:halt, {acc <> snippet, c2}}

          true ->
            snippet = """
            #{if acc == "", do: "if", else: "else if"} (#{cond_code}) {
            #{branch_body}
            }
            """

            {:cont, {acc <> snippet, c2}}
        end
      end)

    after_setup_probe =
      env |> battery_alert_case_probe(:case, :after_setup) |> Host.agent_probe_region()

    after_branches_probe =
      env |> battery_alert_case_probe(:case, :after_branches) |> Host.agent_probe_region()

    code = """
    #{subject_setup}
      ElmcValue *#{out};
      #{after_setup_probe}
      #{branch_code}
      #{after_branches_probe}
    """

    {code, out, final_counter}
  end

  @spec battery_alert_case_probe(Types.compile_env(), term(), atom()) :: String.t()
  defp battery_alert_case_probe(_env, _branch_index, _position), do: ""
end
