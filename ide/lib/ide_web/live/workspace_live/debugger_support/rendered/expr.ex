defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Rendered.Expr do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types

  @type runtime_value :: Types.runtime_value()

  @spec expr_scalar(runtime_value()) :: runtime_value()
  def expr_scalar(%{"type" => "expr"} = node) do
    cond do
      Map.has_key?(node, "value") -> Map.get(node, "value")
      is_binary(Map.get(node, "label")) -> Map.get(node, "label")
      true -> nil
    end
  end

  def expr_scalar(_node), do: nil

  @spec payload_args(runtime_value(), pos_integer()) :: {:ok, [runtime_value()]} | :error
  def payload_args(payload, arity) when is_integer(arity) and arity > 1 do
    flatten_payload(payload, arity, [])
  end

  @spec flatten_payload(runtime_value(), non_neg_integer(), [runtime_value()]) ::
          {:ok, [runtime_value()]} | :error
  defp flatten_payload(value, 1, acc), do: {:ok, Enum.reverse([value | acc])}

  defp flatten_payload(
         %{"type" => "tuple2", "children" => [left, right]},
         remaining,
         acc
       )
       when remaining > 1 do
    flatten_payload(right, remaining - 1, [left | acc])
  end

  defp flatten_payload(_value, _remaining, _acc), do: :error
end
