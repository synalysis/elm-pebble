defmodule ElmEx.Frontend.Pretty.Declaration do
  @moduledoc false

  alias ElmEx.Frontend.Pretty.{Doc, Expr}

  @type opts :: keyword()

  @spec format(map(), opts()) :: Doc.t()
  def format(%{kind: :function_definition} = decl, opts) do
    args = Map.get(decl, :args, [])
    arg_text = if args == [], do: "", else: " " <> Enum.join(args, " ")

    header = Doc.text("#{decl.name}#{arg_text} =")

    body_doc =
      cond do
        is_map(Map.get(decl, :expr)) ->
          Expr.format(decl.expr, opts)

        is_binary(body = Map.get(decl, :body)) and body != "" ->
          Doc.text(String.trim(body))

        true ->
          Doc.text("")
      end

    Doc.concat([header, Doc.nest(1, Doc.concat([Doc.break(), body_doc]))])
  end

  def format(%{kind: :function_signature, name: name, type: type}, opts) do
    prefix = if name in Keyword.get(opts, :ports, []), do: "port ", else: ""
    Doc.text("#{prefix}#{name} : #{type}")
  end

  def format(%{kind: :type_alias, name: name} = decl, _opts) do
    fields = Map.get(decl, :fields, [])
    field_types = Map.get(decl, :field_types, %{})
    extensible_base = Map.get(decl, :extensible_base)

    if fields == [] and is_nil(extensible_base) do
      case Map.get(decl, :alias_type) do
        type when is_binary(type) and type != "" ->
          Doc.text("type alias #{name} = #{type}")

        _ ->
          Doc.text("type alias #{name} = ...")
      end
    else
      Doc.concat([
        Doc.text("type alias #{name} ="),
        Doc.nest(
          1,
          Doc.concat([Doc.break(), format_type_alias_record(fields, field_types, extensible_base)])
        )
      ])
    end
  end

  def format(%{kind: :union, name: name, constructors: constructors}, _opts) do
    case constructors do
      [] ->
        Doc.text("type #{name}")

      [first | rest] ->
        Doc.concat([
          Doc.text("type #{name}"),
          Doc.nest(
            1,
            Doc.concat([
              Doc.break(),
              format_union_constructor(first, :first),
              Doc.concat(
                Enum.map(rest, fn ctor ->
                  Doc.concat([Doc.break(), format_union_constructor(ctor, :rest)])
                end)
              )
            ])
          )
        ])
    end
  end

  def format(other, _opts) do
    Doc.text(inspect(other, limit: :infinity, printable_limit: 120))
  end

  @spec format_type_alias_record([String.t()], %{optional(String.t()) => String.t()}, String.t() | nil) ::
          Doc.t()
  defp format_type_alias_record(fields, field_types, extensible_base) do
    field_docs =
      Enum.map(fields, fn field ->
        type = Map.get(field_types, field, "...")

        Doc.concat([
          Doc.text(field),
          Doc.text(" : "),
          Doc.text(type)
        ])
      end)

    record_open = type_alias_record_open(extensible_base)

    if compact_type_alias_fields?(fields, field_types) do
      Doc.concat([
        record_open,
        Doc.join(field_docs, Doc.text(", ")),
        Doc.text(" }")
      ])
    else
      case field_docs do
        [single] ->
          Doc.concat([record_open, single, Doc.text(" }")])

        [first | rest] ->
          Doc.group(
            Doc.concat([
              record_open,
              first,
              Doc.text(","),
              Doc.nest(
                1,
                Doc.concat([
                  Doc.break(),
                  Doc.concat(
                    Enum.intersperse(rest, Doc.concat([Doc.text(","), Doc.break()]))
                  ),
                  Doc.break(),
                  Doc.text("}")
                ])
              )
            ])
          )

        [] ->
          Doc.concat([record_open, Doc.text("}")])
      end
    end
  end

  @spec type_alias_record_open(String.t() | nil) :: Doc.t()
  defp type_alias_record_open(base) when is_binary(base) do
    Doc.concat([Doc.text("{ "), Doc.text(base), Doc.text(" | ")])
  end

  defp type_alias_record_open(_base), do: Doc.text("{ ")

  @spec compact_type_alias_fields?([String.t()], %{optional(String.t()) => String.t()}) :: boolean()
  defp compact_type_alias_fields?(fields, field_types) do
    length(fields) <= 2 and
      Enum.all?(field_types, fn {_name, type} -> String.length(type) <= 24 end)
  end

  @spec format_union_constructor(map(), :first | :rest) :: Doc.t()
  defp format_union_constructor(%{name: name, arg: nil}, :first), do: Doc.text("= " <> name)

  defp format_union_constructor(%{name: name, arg: arg}, :first) when is_binary(arg),
    do: Doc.text("= " <> name <> " " <> arg)

  defp format_union_constructor(%{name: name, arg: nil}, :rest), do: Doc.text("| " <> name)

  defp format_union_constructor(%{name: name, arg: arg}, :rest) when is_binary(arg),
    do: Doc.text("| " <> name <> " " <> arg)
end
