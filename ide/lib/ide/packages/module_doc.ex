defmodule Ide.Packages.ModuleDoc do
  @moduledoc false

  @doc """
  Converts a single module entry from package.elm-lang.org `docs.json` into Markdown
  suitable for `Ide.Markdown.readme_to_html/1`.
  """
  @spec json_to_markdown(map()) :: String.t()
  def json_to_markdown(mod) when is_map(mod) do
    name = mod["name"] || ""

    sections =
      [
        module_overview(name, mod["comment"]),
        unions_section(mod["unions"]),
        aliases_section(mod["aliases"]),
        values_section("Functions and values", mod["values"]),
        values_section("Operators", mod["binops"])
      ]
      |> Enum.reject(&(&1 == ""))

    Enum.join(sections, "\n\n---\n\n")
  end

  @spec module_overview(term(), term()) :: term()
  defp module_overview("", _), do: ""

  defp module_overview(name, comment) do
    trimmed = String.trim(comment || "")

    if trimmed == "" do
      "# `#{name}`\n"
    else
      "# `#{name}`\n\n#{trimmed}\n"
    end
  end

  @spec unions_section(term()) :: term()
  defp unions_section(nil), do: ""
  defp unions_section([]), do: ""

  defp unions_section(unions) when is_list(unions) do
    blocks =
      Enum.map(unions, fn u ->
        title = u["name"] || "Union"
        args = u["args"] || []
        args_txt = if args == [], do: "", else: " " <> Enum.join(args, " ")
        head = if args_txt == "", do: "### `#{title}`\n", else: "### `#{title}`#{args_txt}\n"
        comment = String.trim(u["comment"] || "")
        cases_txt = format_union_cases(u["cases"] || [])

        parts =
          [head <> if(comment == "", do: "", else: "\n#{comment}\n")]
          |> Enum.reject(&(&1 == ""))

        case_block =
          if cases_txt == "" do
            ""
          else
            "\n**Constructors:** `#{cases_txt}`\n"
          end

        Enum.join(parts, "") <> case_block
      end)

    "## Union types\n\n" <> Enum.join(blocks, "\n\n")
  end

  @spec format_union_cases(term()) :: term()
  defp format_union_cases(cases) when is_list(cases) do
    cases
    |> Enum.map(fn
      [tag, inner] when is_binary(tag) and is_list(inner) ->
        if inner == [] do
          tag
        else
          "#{tag} #{Enum.join(inner, " ")}"
        end

      other ->
        inspect(other)
    end)
    |> Enum.join(" | ")
  end

  @spec aliases_section(term()) :: term()
  defp aliases_section(nil), do: ""
  defp aliases_section([]), do: ""

  defp aliases_section(aliases) when is_list(aliases) do
    blocks =
      Enum.map(aliases, fn a ->
        name = a["name"] || "Alias"
        args = a["args"] || []
        args_txt = if args == [], do: "", else: " " <> Enum.join(args, " ")
        type = a["type"] || ""
        comment = String.trim(a["comment"] || "")

        sig =
          if type == "" do
            ""
          else
            "\n\n```elm\ntype alias #{name}#{args_txt} =\n    #{type}\n```\n"
          end

        "### `#{name}`#{args_txt}\n#{comment}#{sig}"
      end)

    "## Type aliases\n\n" <> Enum.join(blocks, "\n\n")
  end

  @spec values_section(term(), term()) :: term()
  defp values_section(_title, nil), do: ""
  defp values_section(_title, []), do: ""

  defp values_section(title, values) when is_list(values) do
    blocks =
      Enum.map(values, fn v ->
        name = v["name"] || ""
        type = v["type"] || ""
        comment = String.trim(v["comment"] || "")
        extra = value_extra_lines(v)

        sig =
          if type == "" do
            ""
          else
            "\n\n```elm\n#{name} : #{type}\n```\n"
          end

        "### `#{name}`\n#{extra}#{comment}#{sig}"
      end)

    "## #{title}\n\n" <> Enum.join(blocks, "\n\n")
  end

  @spec value_extra_lines(term()) :: term()
  defp value_extra_lines(%{"associativity" => a, "precedence" => p})
       when is_binary(a) and is_integer(p) do
    "**Operator:** associativity `#{a}`, precedence `#{p}`\n\n"
  end

  defp value_extra_lines(_), do: ""
end
