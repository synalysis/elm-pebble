defmodule ElmEx.Frontend.Pretty.Doc do
  @moduledoc """
  Minimal pretty-printing document algebra.

  Documents compose as text, line breaks, and nested blocks. `group/1` marks a
  region that prefers a single line when `render/2` finds it fits the page width.
  """

  alias ElmEx.Frontend.Layout

  @type t() :: :break | {:text, String.t()} | {:concat, t(), t()} | {:nest, pos_integer(), t()} | {:group, t()}

  @spec text(String.t()) :: t()
  def text(string) when is_binary(string), do: {:text, string}

  @spec break() :: t()
  def break, do: :break

  @spec nest(pos_integer(), t()) :: t()
  def nest(level, doc) when is_integer(level) and level >= 0, do: {:nest, level, doc}

  @spec group(t()) :: t()
  def group(doc), do: {:group, doc}

  @doc "Wrap a document in tight parentheses."
  @spec parens(t()) :: t()
  def parens(inner), do: concat([text("("), inner, text(")")])

  @spec concat(t(), t()) :: t()
  def concat(left, right), do: {:concat, left, right}

  @spec concat([t()]) :: t()
  def concat([]), do: text("")

  def concat([doc]), do: doc

  def concat(docs) when is_list(docs) do
    Enum.reduce(docs, text(""), fn doc, acc -> concat(acc, doc) end)
  end

  @doc "Join documents with a separator."
  @spec join([t()], t()) :: t()
  def join([], _sep), do: text("")

  def join([doc], _sep), do: doc

  def join(docs, sep) when is_list(docs) do
    docs |> Enum.intersperse(sep) |> concat()
  end

  @doc "Render a document to a string."
  @spec render(t(), keyword()) :: String.t()
  def render(doc, opts \\ []) do
    width = Keyword.get(opts, :width, 80)
    indent = Keyword.get(opts, :indent, 0)

    doc
    |> render_doc(width, indent, :break)
    |> IO.iodata_to_binary()
  end

  @type mode :: :flat | :break

  @spec render_doc(t(), pos_integer(), non_neg_integer(), mode()) :: iodata()
  defp render_doc(:break, _width, indent, :break), do: ["\n", Layout.spaces(indent)]
  defp render_doc(:break, _width, _indent, :flat), do: " "

  defp render_doc({:text, string}, _width, _indent, _mode), do: string

  defp render_doc({:concat, left, right}, width, indent, mode) do
    [render_doc(left, width, indent, mode), render_doc(right, width, indent, mode)]
  end

  defp render_doc({:nest, level, inner}, width, indent, mode) do
    render_doc(inner, width, indent + level, mode)
  end

  defp render_doc({:group, inner}, width, indent, _mode) do
    flat = render_doc(inner, width, indent, :flat) |> IO.iodata_to_binary()

    if String.length(flat) + Layout.indent_step() * indent <= width do
      flat
    else
      render_doc(inner, width, indent, :break)
    end
  end
end
