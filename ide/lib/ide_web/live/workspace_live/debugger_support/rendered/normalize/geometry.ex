defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Rendered.Normalize.Geometry do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerSupport.Rendered.Expr
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types

  @type runtime_value :: Types.runtime_value()

  @spec point_child(runtime_value()) :: {:ok, {integer(), integer()}} | :error
  def point_child(%{"x" => x, "y" => y}),
    do: {:ok, {scalar_int(x), scalar_int(y)}}

  def point_child(%{x: x, y: y}),
    do: {:ok, {scalar_int(x), scalar_int(y)}}

  def point_child(%{"type" => "expr", "value" => %{"x" => _} = point}),
    do: point_child(point)

  def point_child(%{"type" => "expr"} = node) do
    case Expr.expr_scalar(node) do
      %{"x" => _, "y" => _} = point -> point_child(point)
      _ -> :error
    end
  end

  def point_child(_), do: :error

  @spec rect_child(runtime_value()) ::
          {:ok, {integer(), integer(), integer(), integer()}} | :error
  def rect_child(%{"x" => x, "y" => y, "w" => w, "h" => h}),
    do: {:ok, {scalar_int(x), scalar_int(y), scalar_int(w), scalar_int(h)}}

  def rect_child(%{x: x, y: y, w: w, h: h}),
    do: {:ok, {scalar_int(x), scalar_int(y), scalar_int(w), scalar_int(h)}}

  def rect_child(%{"type" => "expr", "value" => %{"x" => _} = bounds}),
    do: rect_child(bounds)

  def rect_child(%{"type" => "expr"} = node) do
    case Expr.expr_scalar(node) do
      %{"x" => _, "y" => _, "w" => _, "h" => _} = bounds -> rect_child(bounds)
      _ -> :error
    end
  end

  def rect_child(_), do: :error

  @spec scalar_int(runtime_value()) :: integer() | nil
  def scalar_int(value) when is_integer(value), do: value
  def scalar_int(value) when is_float(value), do: trunc(value)

  def scalar_int(%{"type" => "expr"} = node) do
    case Expr.expr_scalar(node) do
      n when is_integer(n) -> n
      n when is_float(n) -> trunc(n)
      _ -> nil
    end
  end

  def scalar_int(_), do: nil

  @spec scalar_color(runtime_value()) :: integer() | nil
  def scalar_color(value) when is_integer(value), do: value

  def scalar_color(%{"type" => "expr"} = node) do
    case Expr.expr_scalar(node) do
      n when is_integer(n) -> n
      _ -> nil
    end
  end

  def scalar_color(_), do: nil
end
