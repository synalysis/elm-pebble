defmodule ElmEx.Frontend.Pretty.Pattern do
  @moduledoc false
  alias ElmEx.Frontend.AstContract.Types, as: Types


  alias ElmEx.Frontend.Pretty.{Doc, Literal}

  @spec format(map()) :: Doc.t()
  def format(%{kind: :wildcard}), do: Doc.text("_")

  def format(%{kind: :var, name: name}), do: Doc.text(name)

  def format(%{kind: :int, value: value}), do: Doc.text(Integer.to_string(value))

  def format(%{kind: :char, value: value}), do: Doc.text(Literal.char_literal(value))

  def format(%{kind: :string, value: value}), do: Doc.text(Literal.string_literal(value))

  def format(%{kind: :tuple, elements: elements}) when is_list(elements) do
    Doc.parens(Doc.join(Enum.map(elements, &format/1), Doc.text(", ")))
  end

  def format(%{kind: :list, elements: elements}) when is_list(elements) do
    format_list_elements(elements)
  end

  def format(%{kind: :cons, head: head, tail: tail}) do
    format_cons_pattern(head, tail)
  end

  def format(%{kind: :constructor, name: "::", bind: bind, arg_pattern: %{kind: :tuple, elements: [head, tail]}})
      when is_binary(bind) do
    Doc.concat([
      Doc.parens(format_cons_pattern(head, tail)),
      Doc.text(" as " <> bind)
    ])
  end

  def format(%{kind: :constructor, name: "::", arg_pattern: %{kind: :tuple, elements: [head, tail]}}) do
    case flatten_list_pattern(head, tail) do
      {:ok, elements} -> format_list_elements(elements)
      :error -> format_cons_pattern(head, tail)
    end
  end

  def format(%{kind: :record, fields: []} = pat) do
    case Map.get(pat, :bind) do
      name when is_binary(name) -> Doc.text("{" <> name <> " |}")
      _ -> Doc.text("{}")
    end
  end

  def format(%{kind: :record, fields: fields} = pat) do
    bind =
      case Map.get(pat, :bind) do
        name when is_binary(name) -> [Doc.text("{"), Doc.text(name), Doc.text(" | ")]
        _ -> [Doc.text("{")]
      end

    Doc.concat(
      bind ++
        [
          Doc.join(Enum.map(fields, &Doc.text/1), Doc.text(", ")),
          Doc.text("}")
        ]
    )
  end

  def format(%{kind: :constructor, name: name} = pat) do
    arg = Map.get(pat, :arg_pattern)
    bind = Map.get(pat, :bind)

    cond do
      not is_nil(arg) ->
        Doc.concat([
          Doc.text(name),
          Doc.text(" "),
          format_constructor_arg(arg),
          if(is_binary(bind), do: Doc.text(" as " <> bind), else: Doc.text(""))
        ])

      is_binary(bind) ->
        Doc.concat([Doc.text(name), Doc.text(" "), Doc.text(bind)])

      true ->
        Doc.text(name)
    end
  end

  def format(%{kind: :unknown, source: source}), do: Doc.text(source)

  def format(other) do
    Doc.text(inspect(other, limit: :infinity, printable_limit: 80))
  end

  @spec format_list_elements(term() | Types.expr()) :: Types.expr()

  defp format_list_elements([]), do: Doc.text("[]")

  defp format_list_elements(elements) do
    item_docs = Enum.map(elements, &format/1)

    if compact_list_pattern_elements?(elements) do
      Doc.concat([Doc.text("["), Doc.join(item_docs, Doc.text(", ")), Doc.text("]")])
    else
      Doc.concat([Doc.text("[ "), Doc.join(item_docs, Doc.text(", ")), Doc.text(" ]")])
    end
  end

  @spec compact_list_pattern_elements?([map()]) :: boolean()
  defp compact_list_pattern_elements?(elements), do: Enum.all?(elements, &compact_list_pattern_element?/1)

  @spec compact_list_pattern_element?(map()) :: boolean()
  defp compact_list_pattern_element?(%{kind: kind})
       when kind in [:var, :wildcard, :int, :char, :string],
       do: true

  defp compact_list_pattern_element?(%{kind: :constructor, arg_pattern: nil}), do: true

  defp compact_list_pattern_element?(%{kind: :list, elements: elements}),
    do: compact_list_pattern_elements?(elements)

  defp compact_list_pattern_element?(_), do: false

  @spec format_cons_pattern(Types.expr(), Types.expr()) :: Types.expr()

  defp format_cons_pattern(head, tail) do
    Doc.concat([
      format_cons_head(head),
      Doc.text(" :: "),
      format(tail)
    ])
  end

  @spec format_cons_head(Types.expr()) :: Types.expr()

  defp format_cons_head(head) do
    if cons_head_needs_parens?(head) do
      Doc.parens(format(head))
    else
      format(head)
    end
  end

  @spec cons_head_needs_parens?(map() | term()) :: boolean()

  defp cons_head_needs_parens?(%{kind: :constructor, arg_pattern: arg}) when not is_nil(arg), do: true
  defp cons_head_needs_parens?(_), do: false

  @spec format_constructor_arg(Types.expr()) :: Types.expr()

  defp format_constructor_arg(arg) do
    if constructor_arg_needs_parens?(arg) do
      Doc.parens(format(arg))
    else
      format(arg)
    end
  end

  @spec constructor_arg_needs_parens?(map() | term()) :: boolean()

  defp constructor_arg_needs_parens?(%{kind: :constructor, bind: bind}) when is_binary(bind), do: true
  defp constructor_arg_needs_parens?(%{kind: :constructor, arg_pattern: arg}) when not is_nil(arg), do: true
  defp constructor_arg_needs_parens?(_), do: false

  @spec flatten_list_pattern(Types.expr(), Types.expr()) :: Types.expr()

  defp flatten_list_pattern(head, tail) do
    case flatten_list_tail(tail) do
      {:ok, rest} -> {:ok, [head | rest]}
      :error -> :error
    end
  end

  @spec flatten_list_tail(map() | term()) :: Types.expr()

  defp flatten_list_tail(%{kind: :constructor, name: "[]", arg_pattern: nil}), do: {:ok, []}

  defp flatten_list_tail(%{kind: :constructor, name: "::", arg_pattern: %{kind: :tuple, elements: [head, tail]}}) do
    case flatten_list_tail(tail) do
      {:ok, rest} -> {:ok, [head | rest]}
      :error -> :error
    end
  end

  defp flatten_list_tail(_), do: :error
end
