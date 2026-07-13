defmodule Elmx.Backend.ElixirCodegen.Emit.Patterns.Case do
  @moduledoc false

  alias Elmx.Backend.ElixirCodegen.Emit.Patterns.Match
  alias Elmx.Types

  @type env :: Types.emit_env()

  def compile_case(%{subject: subject, branches: branches}, env, counter) when is_binary(subject) do
    case_env = maybe_unwrap_just_env(branches, env)

    subj =
      if Elmx.Backend.ElixirCodegen.Emit.Helpers.parameter_binding?(subject, case_env) do
        Elmx.Backend.ElixirCodegen.Emit.Helpers.binding_ref(subject, case_env)
      else
        Elmx.Backend.ElixirCodegen.Emit.Helpers.var_ref(subject, case_env)
      end

    clauses =
      branches
      |> order_case_branches()
      |> Enum.map(&compile_case_branch(&1, case_env, env))

    {["case ", "Elmx.Runtime.Core.Task.force(", subj, ") do\n", Enum.join(clauses, "\n"), "\nend"], env, counter}
  end

  def compile_case(%{subject: subject, branches: branches}, env, counter) do
    case_env = maybe_unwrap_just_env(branches, env)
    {subj, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(subject, case_env, counter)

    clauses =
      branches
      |> order_case_branches()
      |> Enum.map(&compile_case_branch(&1, case_env, env))

    {["case ", "Elmx.Runtime.Core.Task.force(", subj, ") do\n", Enum.join(clauses, "\n"), "\nend"], env, c1}
  end
  defp compile_case_branch(branch, case_env, env) do
    {body, _, _} =
      Elmx.Backend.ElixirCodegen.Emit.compile_expr(branch.expr, Match.branch_env(branch, env), 0)

    body_str = IO.iodata_to_binary(body)

    used_bindings =
      branch
      |> Match.branch_pattern_root()
      |> Match.Bindings.pattern_binding_names()
      |> then(&Elmx.Backend.ElixirCodegen.Emit.Helpers.pattern_bindings_referenced_in_body(body_str, &1))

    branch_case_env = Map.put(case_env, :used_pattern_bindings, used_bindings)
    pattern = Match.branch_pattern(branch, branch_case_env)

    "  #{pattern} ->\n    #{body_str}"
  end

  def order_case_branches(branches) when is_list(branches) do
    branches
    |> Enum.sort_by(&case_branch_sort_key/1)
  end

  def case_branch_sort_key(branch) do
    cond do
      wildcard_case_branch?(branch) -> {2, 0}
      constructor_wildcard_arg_branch?(branch) -> {1, 0}
      true -> {0, 0}
    end
  end

  def wildcard_case_branch?(branch) do
    case Match.branch_pattern_root(branch) do
      %{kind: :wildcard} -> true
      %{kind: :var, name: name} when name in ["_", ""] -> true
      _ -> false
    end
  end

  def constructor_wildcard_arg_branch?(branch) do
    case Match.branch_pattern_root(branch) do
      %{kind: :constructor, arg_pattern: %{kind: :wildcard}} -> true
      _ -> false
    end
  end

  # Elm `case maybe of Nothing -> ...; value -> ...` binds the Just payload, not the wrapper.
  @spec maybe_unwrap_just_env(Types.ir_case_branches(), env()) :: env()
  defp maybe_unwrap_just_env(branches, env) when is_list(branches) do
    if maybe_unwrap_just_case?(branches) do
      Map.put(env, :maybe_unwrap_just, true)
    else
      env
    end
  end

  @spec maybe_unwrap_just_case?(Types.ir_case_branches()) :: boolean()
  defp maybe_unwrap_just_case?(branches) when is_list(branches) do
    Enum.any?(branches, &nothing_branch?/1) and
      Enum.any?(branches, &var_branch?/1) and
      Enum.all?(branches, fn branch -> nothing_branch?(branch) or var_branch?(branch) end)
  end

  @spec nothing_branch?(Types.ir_case_branch()) :: boolean()
  defp nothing_branch?(branch) do
    case Match.branch_pattern_root(branch) do
      %{kind: :constructor, name: name} when name in ["Nothing", "Maybe.Nothing"] -> true
      _ -> false
    end
  end

  @spec var_branch?(Types.ir_case_branch()) :: boolean()
  defp var_branch?(branch) do
    case Match.branch_pattern_root(branch) do
      %{kind: :var, name: name} when is_binary(name) and name not in ["_", ""] -> true
      _ -> false
    end
  end

end
