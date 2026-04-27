defmodule Ide.Formatter.Doc do
  @moduledoc false

  @type t ::
          {:text, String.t()}
          | :line
          | {:concat, [t()]}
          | {:nest, non_neg_integer(), t()}
          | {:group, t()}

  @spec text(String.t()) :: t()
  def text(value) when is_binary(value), do: {:text, value}

  @spec line() :: t()
  def line, do: :line

  @spec concat([t()]) :: t()
  def concat(parts) when is_list(parts), do: {:concat, parts}

  @spec nest(non_neg_integer(), t()) :: t()
  def nest(indent, doc) when is_integer(indent) and indent >= 0, do: {:nest, indent, doc}

  @spec group(t()) :: t()
  def group(doc), do: {:group, doc}

  @spec join([t()], t()) :: t()
  def join([], _sep), do: concat([])
  def join([single], _sep), do: single

  def join([head | rest], sep) do
    concat(
      Enum.reduce(rest, [head], fn part, acc ->
        acc ++ [sep, part]
      end)
    )
  end

  @spec render(t()) :: String.t()
  def render(doc), do: render(doc, 0)

  defp render({:text, value}, _indent), do: value
  defp render(:line, indent), do: "\n" <> String.duplicate(" ", indent)
  defp render({:concat, parts}, indent), do: Enum.map_join(parts, "", &render(&1, indent))
  defp render({:nest, extra, doc}, indent), do: render(doc, indent + extra)
  defp render({:group, doc}, indent), do: render(doc, indent)
end
