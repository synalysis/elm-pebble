defmodule Elmx.Backend.ElixirCodegen.Emit.Patterns.Case do
  @moduledoc false

  alias Elmx.Backend.ElixirCodegen.Emit.Patterns.Match
  alias Elmx.Types

  @type env :: Types.emit_env()

  def compile_case(%{subject: subject, branches: branches}, env, counter) when is_binary(subject) do
    subj =
      if Elmx.Backend.ElixirCodegen.Emit.Helpers.parameter_binding?(subject, env) do
        Elmx.Backend.ElixirCodegen.Emit.Helpers.binding_ref(subject, env)
      else
        Elmx.Backend.ElixirCodegen.Emit.Helpers.var_ref(subject, env)
      end

    clauses =
      branches
      |> order_case_branches()
      |> Enum.map(fn branch ->
        pattern = Match.branch_pattern(branch, env)
        {body, _, _} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(branch.expr, Match.branch_env(branch, env), 0)
        "  #{pattern} ->\n    #{IO.iodata_to_binary(body)}"
      end)

    {["case ", subj, " do\n", Enum.join(clauses, "\n"), "\nend"], env, counter}
  end

  def compile_case(%{subject: subject, branches: branches}, env, counter) do
    {subj, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(subject, env, counter)

    clauses =
      branches
      |> order_case_branches()
      |> Enum.map(fn branch ->
        pattern = Match.branch_pattern(branch, env)
        {body, _, _} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(branch.expr, Match.branch_env(branch, env), 0)
        "  #{pattern} ->\n    #{IO.iodata_to_binary(body)}"
      end)

    {["case ", subj, " do\n", Enum.join(clauses, "\n"), "\nend"], env, c1}
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

end
