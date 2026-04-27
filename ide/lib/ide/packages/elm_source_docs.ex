defmodule Ide.Packages.ElmSourceDocs do
  @moduledoc false

  alias Ide.Packages.ModuleDoc

  @spec list_modules(String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def list_modules(source_root) when is_binary(source_root) do
    if File.dir?(source_root) do
      modules =
        source_root
        |> Path.join("**/*.elm")
        |> Path.wildcard()
        |> Enum.map(&module_name_from_path(&1, source_root))
        |> Enum.reject(&kernel_module?/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> Enum.sort()

      {:ok, modules}
    else
      {:error, :source_root_not_found}
    end
  end

  @spec module_doc_markdown(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def module_doc_markdown(source_root, module_name)
      when is_binary(source_root) and is_binary(module_name) do
    with {:ok, path} <- source_module_path(source_root, module_name),
         {:ok, source} <- File.read(path) do
      mod = source_to_module_doc(source, module_name)
      {:ok, ModuleDoc.json_to_markdown(mod)}
    end
  end

  @spec source_to_module_doc(String.t(), String.t()) :: map()
  def source_to_module_doc(source, module_name)
      when is_binary(source) and is_binary(module_name) do
    lines = String.split(source, "\n", trim: false)

    state = %{
      i: 0,
      pending_doc: nil,
      module_comment: nil,
      seen_declaration: false,
      unions: [],
      aliases: [],
      values: []
    }

    state = parse_lines(lines, state)

    %{
      "name" => module_name,
      "comment" => state.module_comment || "",
      "unions" => Enum.reverse(state.unions),
      "aliases" => Enum.reverse(state.aliases),
      "values" => Enum.reverse(state.values),
      "binops" => []
    }
  end

  @spec source_module_path(term(), term()) :: term()
  defp source_module_path(source_root, module_name) do
    rel =
      module_name
      |> String.split(".")
      |> Path.join()
      |> Kernel.<>(".elm")

    path = Path.join(source_root, rel)

    if File.exists?(path), do: {:ok, path}, else: {:error, :module_source_not_found}
  end

  @spec module_name_from_path(term(), term()) :: term()
  defp module_name_from_path(path, source_root) do
    if String.starts_with?(path, source_root) do
      path
      |> Path.relative_to(source_root)
      |> Path.rootname()
      |> String.split("/")
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(".")
    else
      nil
    end
  end

  @spec kernel_module?(term()) :: term()
  defp kernel_module?(nil), do: false
  defp kernel_module?(name), do: String.starts_with?(name, "Elm.Kernel.")

  @spec parse_lines(term(), term()) :: term()
  defp parse_lines(lines, state) do
    if state.i >= length(lines) do
      state
    else
      line = Enum.at(lines, state.i) || ""
      trimmed = String.trim(line)

      cond do
        String.starts_with?(trimmed, "{-|") ->
          {doc, next_i} = read_doc_block(lines, state.i)
          parse_lines(lines, %{state | pending_doc: doc, i: next_i})

        maybe_assign_module_doc?(trimmed, state) ->
          parse_lines(lines, %{
            state
            | module_comment: state.pending_doc,
              pending_doc: nil,
              i: state.i + 1
          })

        value_signature_line?(trimmed) ->
          state
          |> maybe_promote_pending_to_module_doc()
          |> add_value(lines)
          |> then(&parse_lines(lines, &1))

        type_alias_line?(trimmed) ->
          state
          |> maybe_promote_pending_to_module_doc()
          |> add_type_alias(lines)
          |> then(&parse_lines(lines, &1))

        union_type_line?(trimmed) ->
          state
          |> maybe_promote_pending_to_module_doc()
          |> add_union(lines)
          |> then(&parse_lines(lines, &1))

        true ->
          parse_lines(lines, %{state | i: state.i + 1})
      end
    end
  end

  @spec maybe_assign_module_doc?(term(), term()) :: term()
  defp maybe_assign_module_doc?(trimmed, state) do
    not state.seen_declaration and is_binary(state.pending_doc) and
      is_nil(state.module_comment) and String.starts_with?(trimmed, "import ")
  end

  @spec maybe_promote_pending_to_module_doc(term()) :: term()
  defp maybe_promote_pending_to_module_doc(state) do
    if is_nil(state.module_comment) and is_binary(state.pending_doc) and
         String.contains?(state.pending_doc, "@docs") do
      %{state | module_comment: state.pending_doc, pending_doc: nil}
    else
      state
    end
  end

  @spec read_doc_block(term(), term()) :: term()
  defp read_doc_block(lines, start_i) do
    do_read_doc_block(lines, start_i, [])
  end

  @spec do_read_doc_block(term(), term(), term()) :: term()
  defp do_read_doc_block(lines, i, acc) do
    line = Enum.at(lines, i) || ""
    acc = [line | acc]

    if String.contains?(line, "-}") do
      doc =
        acc
        |> Enum.reverse()
        |> Enum.join("\n")
        |> clean_doc_block()

      {doc, i + 1}
    else
      do_read_doc_block(lines, i + 1, acc)
    end
  end

  @spec clean_doc_block(term()) :: term()
  defp clean_doc_block(text) do
    text
    |> String.replace(~r/\A\s*\{\-\|\s?/, "")
    |> String.replace(~r/\s*\-\}\s*\z/, "")
    |> dedent()
    |> String.trim()
  end

  @spec dedent(term()) :: term()
  defp dedent(text) do
    lines = String.split(text, "\n", trim: false)

    min_indent =
      lines
      |> Enum.reject(&(String.trim(&1) == ""))
      |> Enum.map(fn line ->
        case Regex.run(~r/^\s*/, line) do
          [indent] -> String.length(indent)
          _ -> 0
        end
      end)
      |> case do
        [] -> 0
        values -> Enum.min(values)
      end

    lines
    |> Enum.map(fn line ->
      if String.trim(line) == "" do
        ""
      else
        String.slice(line, min_indent, String.length(line) - min_indent)
      end
    end)
    |> Enum.join("\n")
  end

  @spec value_signature_line?(term()) :: term()
  defp value_signature_line?(trimmed) do
    Regex.match?(~r/^[a-z][A-Za-z0-9_']*\s*:/, trimmed)
  end

  @spec type_alias_line?(term()) :: term()
  defp type_alias_line?(trimmed) do
    String.starts_with?(trimmed, "type alias ")
  end

  @spec union_type_line?(term()) :: term()
  defp union_type_line?(trimmed) do
    String.starts_with?(trimmed, "type ") and not type_alias_line?(trimmed)
  end

  @spec add_value(term(), term()) :: term()
  defp add_value(state, lines) do
    line = Enum.at(lines, state.i) || ""
    trimmed = String.trim(line)
    [_, name, first_type] = Regex.run(~r/^([a-z][A-Za-z0-9_']*)\s*:\s*(.*)$/, trimmed)
    {type, next_i} = read_value_type(lines, state.i + 1, name, [first_type])
    {comment, state} = pop_pending_doc(state)

    value = %{
      "name" => name,
      "type" => String.trim(type),
      "comment" => comment
    }

    %{state | values: [value | state.values], i: next_i, seen_declaration: true}
  end

  @spec read_value_type(term(), term(), term(), term()) :: term()
  defp read_value_type(lines, i, name, acc) do
    if i >= length(lines) do
      {Enum.join(acc, "\n"), i}
    else
      line = Enum.at(lines, i) || ""
      trimmed = String.trim(line)

      cond do
        trimmed == "" ->
          {Enum.join(acc, "\n"), i}

        Regex.match?(~r/^#{name}\b.*=/, trimmed) ->
          {Enum.join(acc, "\n"), i}

        String.starts_with?(line, "    ") or String.starts_with?(line, "\t") ->
          read_value_type(lines, i + 1, name, acc ++ [trimmed])

        true ->
          {Enum.join(acc, "\n"), i}
      end
    end
  end

  @spec add_type_alias(term(), term()) :: term()
  defp add_type_alias(state, lines) do
    line = Enum.at(lines, state.i) || ""
    trimmed = String.trim(line)

    [_, name, arg_text, first_body] =
      Regex.run(~r/^type alias\s+([A-Z][A-Za-z0-9_']*)(.*?)=\s*(.*)$/, trimmed)

    args = parse_args(arg_text)
    {body, next_i} = read_alias_body(lines, state.i + 1, first_body, name)
    {comment, state} = pop_pending_doc(state)

    alias_doc = %{
      "name" => name,
      "args" => args,
      "type" => String.trim(body),
      "comment" => comment
    }

    %{state | aliases: [alias_doc | state.aliases], i: next_i, seen_declaration: true}
  end

  @spec read_alias_body(term(), term(), term(), term()) :: term()
  defp read_alias_body(lines, i, first_body, name) do
    acc = if first_body == "", do: [], else: [first_body]
    do_read_alias_body(lines, i, name, acc)
  end

  @spec do_read_alias_body(term(), term(), term(), term()) :: term()
  defp do_read_alias_body(lines, i, name, acc) do
    if i >= length(lines) do
      {Enum.join(acc, "\n"), i}
    else
      line = Enum.at(lines, i) || ""
      trimmed = String.trim(line)

      cond do
        trimmed == "" ->
          {Enum.join(acc, "\n"), i}

        value_signature_line?(trimmed) or type_alias_line?(trimmed) or union_type_line?(trimmed) ->
          {Enum.join(acc, "\n"), i}

        Regex.match?(~r/^#{name}\b/, trimmed) ->
          {Enum.join(acc, "\n"), i}

        String.starts_with?(line, "    ") or String.starts_with?(line, "\t") ->
          do_read_alias_body(lines, i + 1, name, acc ++ [trimmed])

        true ->
          {Enum.join(acc, "\n"), i}
      end
    end
  end

  @spec add_union(term(), term()) :: term()
  defp add_union(state, lines) do
    line = Enum.at(lines, state.i) || ""
    trimmed = String.trim(line)

    {name, arg_text, first_ctor} =
      case Regex.run(~r/^type\s+([A-Z][A-Za-z0-9_']*)(.*?)=\s*(.*)$/, trimmed) do
        [_, n, a, ctor] ->
          {n, a, ctor}

        _ ->
          case Regex.run(~r/^type\s+([A-Z][A-Za-z0-9_']*)(.*?)$/, trimmed) do
            [_, n, a] -> {n, a, nil}
            _ -> {"", "", nil}
          end
      end

    args = parse_args(arg_text)
    {cases, next_i} = read_union_cases(lines, state.i + 1, first_ctor)
    {comment, state} = pop_pending_doc(state)

    union = %{
      "name" => name,
      "args" => args,
      "cases" => cases,
      "comment" => comment
    }

    %{state | unions: [union | state.unions], i: next_i, seen_declaration: true}
  end

  @spec read_union_cases(term(), term(), term()) :: term()
  defp read_union_cases(lines, i, first_ctor) do
    acc =
      case normalize_ctor(first_ctor) do
        nil -> []
        ctor -> [ctor]
      end

    do_read_union_cases(lines, i, acc)
  end

  @spec do_read_union_cases(term(), term(), term()) :: term()
  defp do_read_union_cases(lines, i, acc) do
    if i >= length(lines) do
      {Enum.reverse(acc), i}
    else
      line = Enum.at(lines, i) || ""
      trimmed = String.trim(line)

      cond do
        trimmed == "" and acc != [] ->
          {Enum.reverse(acc), i}

        String.starts_with?(trimmed, "|") ->
          ctor = normalize_ctor(String.trim_leading(trimmed, "|") |> String.trim())
          next_acc = if ctor, do: [ctor | acc], else: acc
          do_read_union_cases(lines, i + 1, next_acc)

        String.starts_with?(trimmed, "=") ->
          ctor = normalize_ctor(String.trim_leading(trimmed, "=") |> String.trim())
          next_acc = if ctor, do: [ctor | acc], else: acc
          do_read_union_cases(lines, i + 1, next_acc)

        true ->
          {Enum.reverse(acc), i}
      end
    end
  end

  @spec normalize_ctor(term()) :: term()
  defp normalize_ctor(nil), do: nil

  defp normalize_ctor(text) do
    tokens = text |> String.trim() |> String.split(~r/\s+/, trim: true)

    case tokens do
      [] ->
        nil

      [name | args] ->
        [name, args]
    end
  end

  @spec parse_args(term()) :: term()
  defp parse_args(text) do
    text
    |> String.trim()
    |> String.split(~r/\s+/, trim: true)
    |> Enum.reject(&(&1 == ""))
  end

  @spec pop_pending_doc(term()) :: term()
  defp pop_pending_doc(state) do
    case state.pending_doc do
      doc when is_binary(doc) -> {doc, %{state | pending_doc: nil}}
      _ -> {"", state}
    end
  end
end
