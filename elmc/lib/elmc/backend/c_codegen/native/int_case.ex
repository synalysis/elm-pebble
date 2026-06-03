defmodule Elmc.Backend.CCodegen.Native.IntCase do
  @moduledoc false

  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Native.Int, as: NativeInt
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util

  @spec branches?(Types.int_case_branches()) :: boolean()
  def branches?(branches) when is_list(branches) do
    {int_values, wildcard_indexes} =
      branches
      |> Enum.with_index()
      |> Enum.reduce_while({[], []}, fn {branch, index}, {ints, wildcards} ->
        case branch.pattern do
          %{kind: :int, value: value} when is_integer(value) ->
            {:cont, {[value | ints], wildcards}}

          %{kind: :wildcard} ->
            {:cont, {ints, [index | wildcards]}}

          _ ->
            {:halt, {:invalid, :invalid}}
        end
      end)

    case {int_values, wildcard_indexes} do
      {:invalid, :invalid} ->
        false

      {ints, wildcards} ->
        unique_ints? = length(ints) == length(Enum.uniq(ints))
        wildcard_last? = wildcards == [] or wildcards == [length(branches) - 1]
        unique_ints? and wildcard_last?
    end
  end

  def branches?(_branches), do: false

  @spec subject_expr?(Types.ir_expr(), Types.compile_env()) :: boolean()
  def subject_expr?(subject_expr, env) do
    case subject_expr do
      %{op: :var, name: name} when is_binary(name) or is_atom(name) ->
        is_binary(EnvBindings.native_int_binding(env, name))

      _ ->
        NativeInt.expr?(subject_expr, env)
    end
  end

  @spec compile(Types.ir_expr(), Types.int_case_branches(), Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  def compile(subject_expr, branches, env, counter) do
    {subject_code, subject_ref, counter} = NativeInt.compile_expr(subject_expr, env, counter)
    next = counter + 1
    out = "tmp_#{next}"
    exhaustive? = has_default?(branches)
    initial_value = if exhaustive?, do: nil, else: "elmc_int_zero()"

    {branch_code, final_counter} =
      Enum.reduce(branches, {"", next}, fn branch, {acc, c} ->
        {expr_code, assignment_code, c2} =
          Host.compile_case_branch_assignment(branch.expr, out, env, c)

        label = case_label(branch.pattern)
        release_previous = if exhaustive?, do: "", else: "elmc_release(#{out});"

        snippet = """
        #{label}:
        #{Util.indent(expr_code, 4)}
        #{Util.indent(release_previous, 4)}
        #{Util.indent(assignment_code, 4)}
            break;
        """

        {acc <> snippet, c2}
      end)

    code = """
    #{subject_code}
      #{result_decl(out, initial_value)}
      switch (#{subject_ref}) {
      #{branch_code}
      }
    """

    {code, out, final_counter}
  end

  @spec has_default?(Types.int_case_branches()) :: boolean()
  defp has_default?(branches) do
    Enum.any?(branches, fn branch -> match?(%{kind: :wildcard}, branch.pattern) end)
  end

  @spec result_decl(String.t(), String.t() | nil) :: String.t()
  defp result_decl(out, nil), do: "ElmcValue *#{out};"

  defp result_decl(out, initial_value),
    do: "ElmcValue *#{out} = #{initial_value};"

  @spec case_label(Types.int_case_pattern()) :: String.t()
  defp case_label(%{kind: :wildcard}), do: "default"

  defp case_label(%{kind: :int, value: value}) when is_integer(value),
    do: "case #{value}"
end
