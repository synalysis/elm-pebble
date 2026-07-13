defmodule Elmx.Backend.OversaturatedQualified do
  @moduledoc false

  alias Elmx.Backend.QualifiedSaturatedArity
  alias Elmx.Types

  @spec normalize(Types.ir_expr()) :: Types.ir_expr()
  def normalize(%{op: :qualified_call, target: target, args: args}) when is_binary(target) and is_list(args) do
    case QualifiedSaturatedArity.saturated(target) do
      {:ok, arity} when length(args) > arity ->
        apply_extra(target, args, arity)

      _ ->
        %{op: :qualified_call, target: target, args: args}
    end
  end

  def normalize(expr), do: expr

  defp apply_extra(target, args, arity) do
    {bound, extra} = Enum.split(args, arity)

    Enum.reduce(extra, %{op: :qualified_call, target: target, args: bound}, fn arg, acc ->
      %{op: :call, name: "__apply__", args: [acc, arg]}
    end)
  end
end
