defmodule Ide.Lsp.Server do
  @moduledoc false

  alias Ide.EditorCompletion
  alias Ide.EditorDocLinks
  alias Ide.ElmFormat
  alias Ide.Formatter
  alias Ide.Projects
  alias Ide.Settings
  alias Ide.Tokenizer
  alias IdeWeb.WorkspaceLive.EditorDependencies

  @min_fold_span_lines 10

  @type state :: %{
          project_slug: String.t(),
          documents: map(),
          dependency_payloads: map()
        }

  @spec new(String.t()) :: state()
  def new(project_slug) when is_binary(project_slug) do
    %{project_slug: project_slug, documents: %{}, dependency_payloads: %{}}
  end

  @spec handle(String.t(), state()) :: {[map()], state()}
  def handle(raw, state) when is_binary(raw) do
    case Jason.decode(raw) do
      {:ok, %{"method" => method} = message} ->
        dispatch(method, message, state)

      {:ok, %{"id" => id}} ->
        {[error_response(id, -32600, "Unexpected response message.")], state}

      _ ->
        {[error_response(nil, -32700, "Parse error.")], state}
    end
  end

  @spec dispatch(String.t(), map(), state()) :: {[map()], state()}
  defp dispatch("initialize", %{"id" => id}, state) do
    {[response(id, initialize_result())], state}
  end

  defp dispatch("initialized", _message, state), do: {[], state}

  defp dispatch("shutdown", %{"id" => id}, state), do: {[response(id, nil)], state}
  defp dispatch("exit", _message, state), do: {[], state}

  defp dispatch("textDocument/didOpen", %{"params" => params}, state) do
    doc = get_in(params, ["textDocument"]) || %{}
    uri = doc["uri"]
    text = doc["text"] || ""
    version = doc["version"] || 0
    state = put_document(state, uri, text, version)
    {diagnostic_notifications(uri, text, version), state}
  end

  defp dispatch("textDocument/didChange", %{"params" => params}, state) do
    uri = get_in(params, ["textDocument", "uri"])
    version = get_in(params, ["textDocument", "version"]) || 0
    text = changed_text(params["contentChanges"], document_text(state, uri))
    state = put_document(state, uri, text, version)
    {diagnostic_notifications(uri, text, version), state}
  end

  defp dispatch("textDocument/didClose", %{"params" => params}, state) do
    uri = get_in(params, ["textDocument", "uri"])
    state = %{state | documents: Map.delete(state.documents, uri)}
    {[publish_diagnostics(uri, [], nil)], state}
  end

  defp dispatch("textDocument/formatting", %{"id" => id, "params" => params}, state) do
    uri = get_in(params, ["textDocument", "uri"])
    text = document_text(state, uri)

    result =
      with {:ok, formatted} <- format_document(uri, text, state) do
        if formatted == text do
          []
        else
          [%{"range" => whole_document_range(text), "newText" => formatted}]
        end
      end

    case result do
      {:error, reason} -> {[error_response(id, -32603, lsp_error_message(reason))], state}
      edits -> {[response(id, edits)], state}
    end
  end

  defp dispatch("textDocument/completion", %{"id" => id, "params" => params}, state) do
    uri = get_in(params, ["textDocument", "uri"])
    document = document(state, uri)
    text = document[:text] || ""
    position = params["position"] || %{}
    offset = offset_at_position(text, position)
    prefix = completion_prefix(String.slice(text, 0, offset))
    {dependency_payload, state} = cached_dependency_payload(uri, state)

    items =
      dependency_payload
      |> Map.take([:package_doc_index, :editor_doc_packages, :direct, :indirect])
      |> Map.merge(%{
        prefix: prefix,
        parser_payload: document[:parser_payload],
        token_tokens: document[:tokens] || [],
        limit: 50
      })
      |> EditorCompletion.suggest()
      |> Enum.map(&completion_item/1)

    {[response(id, %{"isIncomplete" => false, "items" => items})], state}
  end

  defp dispatch("textDocument/hover", %{"id" => id, "params" => params}, state) do
    uri = get_in(params, ["textDocument", "uri"])
    text = document_text(state, uri)
    offset = offset_at_position(text, params["position"] || %{})
    {dependency_payload, state} = cached_dependency_payload(uri, state)
    docs = dependency_payload.package_doc_index

    result =
      case EditorDocLinks.resolve(text, offset, docs) do
        {:ok, %{url: url, package: package, module: module_name, symbol: symbol}} ->
          %{
            "contents" => %{
              "kind" => "markdown",
              "value" => "[#{module_name}.#{symbol}](#{url})\n\n#{package}"
            }
          }

        _ ->
          nil
      end

    {[response(id, result)], state}
  end

  defp dispatch("textDocument/foldingRange", %{"id" => id, "params" => params}, state) do
    uri = get_in(params, ["textDocument", "uri"])
    ranges = state |> document_text(uri) |> folding_ranges()
    {[response(id, ranges)], state}
  end

  defp dispatch("textDocument/definition", %{"id" => id}, state), do: {[response(id, nil)], state}

  defp dispatch("textDocument/documentLink", %{"id" => id}, state),
    do: {[response(id, [])], state}

  defp dispatch(_method, %{"id" => id}, state) do
    {[error_response(id, -32601, "Method not found.")], state}
  end

  defp dispatch(_method, _message, state), do: {[], state}

  @spec initialize_result() :: map()
  defp initialize_result do
    %{
      "capabilities" => %{
        "textDocumentSync" => %{"openClose" => true, "change" => 1},
        "documentFormattingProvider" => true,
        "completionProvider" => %{"triggerCharacters" => ["."]},
        "foldingRangeProvider" => true,
        "hoverProvider" => true,
        "definitionProvider" => true,
        "documentLinkProvider" => %{"resolveProvider" => false}
      },
      "serverInfo" => %{"name" => "Elm Pebble IDE LSP", "version" => "0.1.0"}
    }
  end

  defp put_document(state, uri, text, version) when is_binary(uri) do
    tokenizer = Tokenizer.tokenize(text, mode: :fast)

    document = %{
      text: text,
      version: version,
      tokens: tokenizer.tokens,
      parser_payload: tokenizer.formatter_parser_payload,
      diagnostics: tokenizer.diagnostics
    }

    %{state | documents: Map.put(state.documents, uri, document)}
  end

  defp put_document(state, _uri, _text, _version), do: state

  defp document_text(state, uri) do
    get_in(state.documents, [uri, :text]) || ""
  end

  defp document(state, uri) do
    Map.get(state.documents, uri, %{})
  end

  defp changed_text([%{"text" => text} | _], _previous) when is_binary(text), do: text
  defp changed_text(_, previous), do: previous || ""

  defp diagnostic_notifications(uri, text, version) do
    diagnostics =
      text
      |> Tokenizer.tokenize(mode: :fast)
      |> Map.get(:diagnostics, [])
      |> Enum.map(&lsp_diagnostic/1)

    [publish_diagnostics(uri, diagnostics, version)]
  end

  defp publish_diagnostics(uri, diagnostics, version) do
    params = %{"uri" => uri, "diagnostics" => diagnostics}
    params = if is_integer(version), do: Map.put(params, "version", version), else: params
    notification("textDocument/publishDiagnostics", params)
  end

  defp lsp_diagnostic(diag) do
    line = max((diag[:line] || 1) - 1, 0)
    col = max((diag[:column] || 1) - 1, 0)
    end_line = max((diag[:end_line] || diag[:line] || 1) - 1, 0)
    end_col = max((diag[:end_column] || (diag[:column] || 1) + 1) - 1, col + 1)

    %{
      "range" => %{
        "start" => %{"line" => line, "character" => col},
        "end" => %{"line" => end_line, "character" => end_col}
      },
      "severity" => diagnostic_severity(diag[:severity]),
      "source" => diag[:source] || "elm-pebble",
      "message" => diag[:message] || inspect(diag)
    }
  end

  defp diagnostic_severity("error"), do: 1
  defp diagnostic_severity("warning"), do: 2
  defp diagnostic_severity("warn"), do: 2
  defp diagnostic_severity("info"), do: 3
  defp diagnostic_severity(_), do: 3

  defp format_document(uri, text, state) do
    case Settings.current().formatter_backend do
      :elm_format ->
        cwd = uri |> decode_uri() |> source_root_path(state)
        with {:ok, result} <- ElmFormat.format(text, cwd: cwd), do: {:ok, result.formatted_source}

      _ ->
        with {:ok, result} <- Formatter.format(text, rel_path: rel_path_from_uri(uri)),
             do: {:ok, result.formatted_source}
    end
  end

  defp cached_dependency_payload(uri, state) do
    cache_key = dependency_payload_cache_key(uri)

    case Map.fetch(state.dependency_payloads, cache_key) do
      {:ok, payload} ->
        {payload, state}

      :error ->
        payload = dependency_payload(uri)

        {payload,
         %{state | dependency_payloads: Map.put(state.dependency_payloads, cache_key, payload)}}
    end
  end

  defp dependency_payload_cache_key(uri) do
    case decode_uri(uri) do
      {:ok, %{project_slug: slug, source_root: source_root}} -> {slug, source_root}
      _ -> {:unknown, uri}
    end
  end

  defp dependency_payload(uri) do
    with {:ok, %{project_slug: slug, source_root: source_root}} <- decode_uri(uri),
         %{source_roots: source_roots} = project <- Projects.get_project_by_slug(slug) do
      packages_root =
        if source_root in source_roots do
          source_root
        else
          List.first(source_roots) || source_root
        end

      EditorDependencies.build_payload(project, packages_root, source_root)
    else
      _ ->
        %{
          package_doc_index: %{},
          editor_doc_packages: [],
          direct: [],
          indirect: []
        }
    end
  end

  defp source_root_path({:ok, %{project_slug: slug, source_root: source_root}}, _state) do
    case Projects.get_project_by_slug(slug) do
      nil -> File.cwd!()
      project -> project |> Projects.project_workspace_path() |> Path.join(source_root)
    end
  end

  defp source_root_path(_, _state), do: File.cwd!()

  defp rel_path_from_uri(uri) do
    case decode_uri(uri) do
      {:ok, %{rel_path: rel_path}} -> rel_path
      _ -> nil
    end
  end

  defp decode_uri("elm-pebble://" <> rest) do
    with [slug, source_root, rel_path] <- String.split(rest, "/", parts: 3) do
      {:ok,
       %{
         project_slug: URI.decode(slug),
         source_root: URI.decode(source_root),
         rel_path: URI.decode(rel_path)
       }}
    else
      _ -> :error
    end
  end

  defp decode_uri(_), do: :error

  defp whole_document_range(text) do
    lines = String.split(text, "\n", trim: false)
    last_line = max(length(lines) - 1, 0)
    last_col = lines |> List.last() |> to_string() |> String.length()

    %{
      "start" => %{"line" => 0, "character" => 0},
      "end" => %{"line" => last_line, "character" => last_col}
    }
  end

  defp offset_at_position(text, %{"line" => line, "character" => character}) do
    lines = String.split(text, "\n", trim: false)

    {prefix_lines, line_text} =
      case Enum.split(lines, max(line, 0)) do
        {prefix, [current | _]} -> {prefix, current}
        {prefix, []} -> {prefix, ""}
      end

    prefix_len = prefix_lines |> Enum.map(&(String.length(&1) + 1)) |> Enum.sum()
    prefix_len + min(max(character, 0), String.length(line_text))
  end

  defp offset_at_position(_text, _position), do: 0

  defp completion_prefix(prefix_text) do
    case Regex.run(~r/([A-Za-z_][A-Za-z0-9_']*)$/, prefix_text) do
      [_, prefix] -> prefix
      _ -> ""
    end
  end

  defp completion_item(item) do
    %{
      "label" => item.label,
      "insertText" => item.insert_text,
      "kind" => completion_kind(item.kind),
      "detail" => item.source
    }
  end

  defp completion_kind("keyword"), do: 14
  defp completion_kind("module"), do: 9
  defp completion_kind("package"), do: 9
  defp completion_kind("symbol"), do: 6
  defp completion_kind(_), do: 1

  defp folding_ranges(text) do
    lines = String.split(text, "\n", trim: false)

    lines
    |> Enum.with_index()
    |> Enum.flat_map(fn {line, idx} ->
      indent = leading_indent(line)
      trimmed = String.trim(line)

      cond do
        trimmed == "" ->
          []

        let_start_line?(trimmed) ->
          case matching_in_line(lines, idx + 1, indent) do
            in_idx when is_integer(in_idx) and in_idx - idx > @min_fold_span_lines ->
              [%{"startLine" => idx, "endLine" => in_idx - 1}]

            _ ->
              []
          end

        String.ends_with?(trimmed, "=") or String.ends_with?(trimmed, "->") or
          String.starts_with?(trimmed, "type ") or String.starts_with?(trimmed, "case ") ->
          case next_less_or_equal_indent(lines, idx + 1, indent) do
            end_idx when is_integer(end_idx) and end_idx - idx > @min_fold_span_lines ->
              [%{"startLine" => idx, "endLine" => end_idx - 1}]

            _ ->
              []
          end

        true ->
          []
      end
    end)
    |> Enum.take(500)
  end

  defp let_start_line?(trimmed) when is_binary(trimmed), do: Regex.match?(~r/^let\b/, trimmed)

  defp matching_in_line(lines, idx, indent) do
    lines
    |> Enum.with_index()
    |> Enum.drop(idx)
    |> Enum.find_value(fn {line, line_idx} ->
      trimmed = String.trim(line)

      cond do
        trimmed == "" ->
          nil

        leading_indent(line) == indent and Regex.match?(~r/^in\b/, trimmed) ->
          line_idx

        leading_indent(line) < indent ->
          :not_found

        true ->
          nil
      end
    end)
    |> case do
      :not_found -> nil
      value -> value
    end
  end

  defp next_less_or_equal_indent(lines, idx, indent) do
    lines
    |> Enum.with_index()
    |> Enum.drop(idx)
    |> Enum.find_value(length(lines), fn {line, line_idx} ->
      if String.trim(line) != "" and leading_indent(line) <= indent do
        line_idx
      else
        nil
      end
    end)
  end

  defp leading_indent(line) do
    String.length(line) - String.length(String.trim_leading(line))
  end

  defp response(id, result), do: %{"jsonrpc" => "2.0", "id" => id, "result" => result}

  defp error_response(id, code, message) do
    %{"jsonrpc" => "2.0", "id" => id, "error" => %{"code" => code, "message" => message}}
  end

  defp notification(method, params),
    do: %{"jsonrpc" => "2.0", "method" => method, "params" => params}

  defp lsp_error_message(reason) when is_map(reason), do: reason[:message] || inspect(reason)
end
