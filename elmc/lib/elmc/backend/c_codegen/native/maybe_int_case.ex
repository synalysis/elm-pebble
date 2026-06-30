defmodule Elmc.Backend.CCodegen.Native.MaybeIntCase do
  @moduledoc false

  alias Elmc.Backend.CCodegen.CaseCompile
  alias Elmc.Backend.CCodegen.ConstructorTagCase
  alias Elmc.Backend.CCodegen.CSource
  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Expr
  alias Elmc.Backend.CCodegen.Native.Int, as: NativeInt
  alias Elmc.Backend.CCodegen.Patterns
  alias Elmc.Backend.CCodegen.RecordCompile
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.ValueSlots

  @spec branches?(list()) :: boolean()
  def branches?(branches) when is_list(branches) do
    match?({:ok, _, _}, classify(branches))
  end

  def branches?(_branches), do: false

  @spec subject_expr?(Types.ir_expr(), Types.compile_env()) :: boolean()
  def subject_expr?(subject_expr, env) do
    not NativeInt.expr?(subject_expr, env)
  end

  @spec branch_env(
          Types.case_branch(),
          Types.ir_expr(),
          list(),
          Types.compile_env()
        ) :: Types.compile_env()
  def branch_env(branch, subject_expr, branches, env) do
    env = put_case_subject_payload_type(env, subject_expr)

    cond do
      Patterns.maybe_unwrap_just_case?(branches) and var_branch?(branch) ->
        env
        |> Map.put(:maybe_unwrap_just, true)
        |> Patterns.bind_pattern(branch.pattern, "tmp_subject")

      just_branch?(branch) ->
        Patterns.bind_pattern(env, branch.pattern, "tmp_subject")

      true ->
        env
    end
  end

  @spec compile_scalar(
          Types.case_subject(),
          list(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.native_scalar_compile_result()
  def compile_scalar(subject, branches, env, counter) do
    subject_expr = CaseCompile.subject_expr(subject)
    {:ok, just_branch, nothing_branch} = classify(branches)

    {subject_code, subject_ref, counter} =
      ConstructorTagCase.compile_subject_ref(subject_expr, env, counter)

    case_env = put_case_subject_payload_type(env, subject_expr)
    just_cond = Patterns.pattern_condition(subject_ref, just_branch.pattern, case_env)

    {just_env, just_setup, counter} =
      build_just_branch_env(case_env, just_branch, subject_ref, subject_expr, branches, counter)

    {just_code, just_ref, counter} =
      NativeInt.compile_expr(just_branch.expr, just_env, counter)

    {nothing_code, nothing_ref, counter} =
      NativeInt.compile_expr(nothing_branch.expr, case_env, counter)

    next = counter + 1
    out = "native_maybe_case_#{next}"

    subject_release =
      if subject_code != "" and not EnvBindings.borrowed_arg_ref?(env, subject_ref) do
        ValueSlots.release_stmt(subject_ref)
      else
        ""
      end

    code = """
    #{subject_code}
      #{just_setup}
      elmc_int_t #{out};
      if (#{just_cond}) {
    #{CSource.indent(just_code, 4)}
        #{out} = #{just_ref};
      } else {
    #{CSource.indent(nothing_code, 4)}
        #{out} = #{nothing_ref};
      }
      #{subject_release}
    """

    {code, out, next}
  end

  @spec classify(list()) :: {:ok, map(), map()} | :error
  defp classify(branches) do
    cond do
      Patterns.maybe_unwrap_just_case?(branches) ->
        with %{pattern: %{kind: :var}} = just <- Enum.find(branches, &var_branch?/1),
             nothing <- Enum.find(branches, &nothing_branch?/1) do
          {:ok, just, nothing}
        else
          _ -> :error
        end

      true ->
        with just <- Enum.find(branches, &just_branch?/1),
             nothing <- Enum.find(branches, &nothing_branch?/1),
             true <- just != nil and nothing != nil,
             true <- length(branches) == 2 do
          {:ok, just, nothing}
        else
          _ -> :error
        end
    end
  end

  defp build_just_branch_env(env, branch, subject_ref, subject_expr, branches, counter) do
    if Patterns.maybe_unwrap_just_case?(branches) and var_branch?(branch) do
      {branch_env, setup, _release, counter} =
        Patterns.maybe_unwrap_var_branch(
          Map.put(env, :maybe_unwrap_just, true),
          branch,
          subject_ref,
          counter,
          subject_expr
        )

      {branch_env, setup, counter}
    else
      branch_env =
        env
        |> RecordCompile.fresh_subexpr_cache()
        |> Patterns.bind_pattern(branch.pattern, subject_ref)

      {branch_env, "", counter}
    end
  end

  defp put_case_subject_payload_type(env, subject_expr) do
    case Expr.maybe_unwrapped_record_type(subject_expr, env) do
      type when is_binary(type) -> Map.put(env, :__case_subject_payload_type__, type)
      _ -> env
    end
  end

  defp just_branch?(%{pattern: %{kind: :constructor, name: name}})
       when name in ["Just", "Maybe.Just"],
       do: true

  defp just_branch?(_), do: false

  defp nothing_branch?(%{pattern: %{kind: :constructor, name: name}})
       when name in ["Nothing", "Maybe.Nothing"],
       do: true

  defp nothing_branch?(%{pattern: %{kind: :wildcard}}), do: true

  defp nothing_branch?(_), do: false

  defp var_branch?(%{pattern: %{kind: :var, name: name}})
       when name not in [nil, "", "_"],
       do: true

  defp var_branch?(_), do: false
end
