defmodule Elmx.Backend.UnsupportedOpError do
  @moduledoc false
  defexception [:op, :expr, message: "unsupported IR op for Elmx backend"]

  @impl true
  def exception(opts) do
    op = Keyword.get(opts, :op)
    expr = Keyword.get(opts, :expr)

    detail =
      case expr do
        %{target: target} when is_binary(target) -> " (#{target})"
        _ -> ""
      end

    %__MODULE__{
      op: op,
      expr: expr,
      message: "unsupported Elmx backend op: #{inspect(op)}#{detail}"
    }
  end
end
