defmodule ElmEx.IR.PipeChain do
  @moduledoc """
  Desugars flat `pipe_chain` IR into nested call/qualified_call nodes.

  The expression parser emits `pipe_chain` for long `|>` sequences. elmx lowers
  that form directly; other backends (elmc) desugar back to the nested shape
  fusion and call lowering already understand.
  """

  alias ElmEx.IR.Types.Expr, as: Expr

  @flatten_threshold 16

  @spec desugar(Expr.t()) :: Expr.t()
  def desugar(%{op: :pipe_chain, steps: steps, base: base} = expr) when is_list(steps) do
    {homogeneous_prefix, _rest} = split_homogeneous_prefix(steps)

    if length(homogeneous_prefix) >= @flatten_threshold do
      expr
    else
      Enum.reduce(steps, base, &append_pipe_arg/2)
    end
  end

  def desugar(expr), do: expr

  @spec desugar_expr(Expr.t() | nil) :: Expr.t() | nil
  def desugar_expr(nil), do: nil

  def desugar_expr(%{} = expr) do
    expr
    |> desugar()
    |> desugar_children()
  end

  def desugar_expr(other), do: other

  @spec desugar_project(map()) :: map()
  def desugar_project(%{modules: modules} = ir) when is_list(modules) do
    %{ir | modules: Enum.map(modules, &desugar_module/1)}
  end

  def desugar_project(ir), do: ir

  defp desugar_module(%{declarations: decls} = mod) when is_list(decls) do
    %{mod | declarations: Enum.map(decls, &desugar_declaration/1)}
  end

  defp desugar_module(mod), do: mod

  defp desugar_declaration(%{expr: expr} = decl) when is_map(expr) do
    %{decl | expr: desugar_expr(expr)}
  end

  defp desugar_declaration(decl), do: decl

  defp desugar_children(%{op: :pipe_chain} = expr), do: desugar(expr)

  defp desugar_children(%{} = expr) do
    Enum.into(expr, %{}, fn
      {key, child} when is_map(child) -> {key, desugar_expr(child)}
      {key, children} when is_list(children) -> {key, Enum.map(children, &desugar_child/1)}
      {key, other} -> {key, other}
    end)
  end

  defp desugar_child(%{} = child), do: desugar_expr(child)
  defp desugar_child(child), do: child

  @spec append_pipe_arg(Expr.t(), Expr.t()) :: Expr.t()
  def append_pipe_arg(%{op: :qualified_call, target: target, args: args}, acc)
       when is_binary(target) and is_list(args) do
    %{op: :qualified_call, target: target, args: args ++ [acc]}
  end

  def append_pipe_arg(%{op: :call, name: name, args: args}, acc)
       when is_binary(name) and is_list(args) do
    %{op: :call, name: name, args: args ++ [acc]}
  end

  def append_pipe_arg(%{op: :var, name: name}, acc) when is_binary(name) do
    %{op: :call, name: name, args: [acc]}
  end

  def append_pipe_arg(%{op: :qualified_ref, target: target}, acc) when is_binary(target) do
    %{op: :qualified_call, target: target, args: [acc]}
  end

  def append_pipe_arg(%{op: :constructor_ref, target: target}, acc) when is_binary(target) do
    %{op: :constructor_call, target: target, args: [acc]}
  end

  def append_pipe_arg(step, acc) do
    %{op: :call, name: "__apply__", args: [step, acc]}
  end

  defp split_homogeneous_prefix([]), do: {[], []}

  defp split_homogeneous_prefix([first | rest]) do
    {same, other} = Enum.split_while(rest, &(&1 == first))
    {[first | same], other}
  end
end
