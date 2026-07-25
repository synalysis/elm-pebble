defmodule ElmEx.Frontend.Pretty.Declaration do
  @moduledoc false

  alias ElmEx.Frontend.Pretty.{BodyLayout, Doc, Expr}

  @type opts :: keyword()

  @spec format(map(), opts()) :: Doc.t()
  def format(%{kind: :function_definition} = decl, opts) do
    args = Map.get(decl, :args, [])
    arg_text = if args == [], do: "", else: " " <> Enum.join(args, " ")

    header =
      if header_source = Map.get(decl, :header_source) do
        Doc.text(String.trim_trailing(header_source))
      else
        Doc.text("#{decl.name}#{arg_text} =")
      end

    body_doc =
      cond do
        is_binary(body = Map.get(decl, :body)) and body != "" ->
          Doc.text(BodyLayout.normalize_function_body(body))

        is_map(Map.get(decl, :expr)) ->
          Expr.format(decl.expr, opts)

        true ->
          Doc.text("")
      end

    if is_binary(Map.get(decl, :body)) and Map.get(decl, :body) != "" do
      Doc.concat([header, Doc.break(), body_doc])
    else
      Doc.concat([header, Doc.nest(1, Doc.concat([Doc.break(), body_doc]))])
    end
  end

  def format(%{kind: :function_signature, name: name, type: type} = decl, opts) do
    if source = Map.get(decl, :source) do
      Doc.text(source)
    else
      prefix = if name in Keyword.get(opts, :ports, []), do: "port ", else: ""
      Doc.text("#{prefix}#{name} : #{type}")
    end
  end

  def format(%{kind: :raw, source: source}, _opts) when is_binary(source) do
    Doc.text(String.trim_trailing(source))
  end

  def format(%{kind: :type_alias, name: name} = decl, _opts) do
    if source = Map.get(decl, :source) do
      Doc.text(source |> normalize_type_alias_source() |> String.trim_trailing())
    else
      format_type_alias_decl(name, decl)
    end
  end

  def format(%{kind: :union, name: name} = decl, _opts) do
    if source = Map.get(decl, :source) do
      Doc.text(source |> normalize_union_source() |> String.trim_trailing())
    else
      format_union_from_ast(name, Map.get(decl, :type_params, []), Map.get(decl, :constructors, []))
    end
  end

  def format(other, _opts) do
    Doc.text(inspect(other, limit: :infinity, printable_limit: 120))
  end

  defp format_type_alias_decl(name, decl) do
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
          Doc.concat([
            record_open,
            first,
            Doc.concat(
              Enum.map(rest, fn field_doc ->
                Doc.concat([Doc.break(), Doc.text(", "), field_doc])
              end)
            ),
            Doc.break(),
            Doc.text("}")
          ])

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
    length(fields) <= 1 and
      Enum.all?(field_types, fn {_name, type} -> String.length(type) <= 24 end)
  end

  @spec format_union_from_ast(String.t(), [String.t()], [map()]) :: Doc.t()
  defp format_union_from_ast(name, type_params, constructors) do
    params_text =
      case type_params do
        [] -> ""
        params -> " " <> Enum.join(params, " ")
      end

    case constructors do
      [] ->
        Doc.text("type #{name}#{params_text}")

      [first | rest] ->
        Doc.concat([
          Doc.text("type #{name}#{params_text}"),
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

  @spec format_union_constructor(map(), :first | :rest) :: Doc.t()
  defp format_union_constructor(%{name: name, arg: nil}, :first), do: Doc.text("= " <> name)

  defp format_union_constructor(%{name: name, arg: arg}, :first) when is_binary(arg),
    do: Doc.text("= " <> name <> " " <> arg)

  defp format_union_constructor(%{name: name, arg: nil}, :rest), do: Doc.text("| " <> name)

  defp format_union_constructor(%{name: name, arg: arg}, :rest) when is_binary(arg),
    do: Doc.text("| " <> name <> " " <> arg)

  @spec normalize_union_source(String.t()) :: String.t()
  defp normalize_union_source(source) when is_binary(source) do
    source
    |> String.split("\n", trim: false)
    |> Enum.map_join("\n", &normalize_union_source_line/1)
  end

  @spec normalize_union_source_line(String.t()) :: String.t()
  defp normalize_union_source_line(line) when is_binary(line) do
    Regex.replace(~r/^(\s*(?:=|\|)\s+\S+)\s{2,}/u, line, "\\1 ")
  end

  @spec normalize_type_alias_source(String.t()) :: String.t()
  defp normalize_type_alias_source(source) when is_binary(source) do
    case String.split(source, "\n", parts: 2) do
      [head] ->
        normalize_type_alias_head(head)

      [head, tail] ->
        normalize_type_alias_head(head) <> "\n" <> tail
    end
  end

  defp normalize_type_alias_head(head) do
    case Regex.run(~r/^(type\s+alias)\s+([A-Z][A-Za-z0-9_']*)\s*=(.*)$/u, String.trim_trailing(head)) do
      [_, keyword, name, rest] -> "#{keyword} #{name} =#{rest}"
      _ -> head
    end
  end
end
