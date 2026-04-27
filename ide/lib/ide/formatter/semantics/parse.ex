defmodule Ide.Formatter.Semantics.Parse do
  @moduledoc false
  alias Ide.Formatter.Semantics.HeaderMetadata

  @type parse_payload :: %{
          diagnostics: [map()],
          metadata: HeaderMetadata.metadata(),
          source_hash: integer(),
          reused?: boolean(),
          fallback?: boolean()
        }

  @spec validate_with_parser(String.t(), keyword()) :: {:ok, parse_payload()} | {:error, map()}
  def validate_with_parser(source, opts \\ []) when is_binary(source) do
    with {:ok, payload} <- maybe_use_precomputed_payload(source, opts) do
      {:ok, payload}
    else
      :continue -> parse_source(source)
    end
  end

  @spec source_hash(String.t()) :: integer()
  def source_hash(source) when is_binary(source), do: :erlang.phash2(source)

  @spec maybe_use_precomputed_payload(term(), term()) :: term()
  defp maybe_use_precomputed_payload(source, opts) do
    with payload when is_map(payload) <- Keyword.get(opts, :parser_payload),
         true <- valid_payload_shape?(payload),
         true <- payload.source_hash == source_hash(source) do
      {:ok, payload |> Map.put(:reused?, true) |> Map.put_new(:fallback?, false)}
    else
      _ -> :continue
    end
  end

  @spec parse_source(term()) :: term()
  defp parse_source(source) do
    with :ok <- ensure_elm_ex_modules_loaded(),
         {:ok, values, tokens} <- parse_metadata_values(source) do
      {:ok,
       %{
         diagnostics: [],
         metadata: HeaderMetadata.from_values_and_tokens(source, values, tokens),
         source_hash: source_hash(source),
         reused?: false,
         fallback?: false
       }}
    else
      {:error, %{line: line, column: column, message: message}} ->
        if unsupported_parse_reason?(message) do
          {:ok,
           %{
             diagnostics: [
               %{
                 severity: "warning",
                 source: "formatter/parser",
                 message:
                   "Fallback formatting used due to unsupported parser feature: #{message}",
                 line: line,
                 column: column
               }
             ],
             metadata: infer_metadata_without_parser(source),
             source_hash: source_hash(source),
             reused?: false,
             fallback?: true
           }}
        else
          {:error,
           %{
             severity: "error",
             source: "formatter/parser",
             message: "Cannot format: #{message}",
             line: line,
             column: column
           }}
        end

      {:error, reason} ->
        {:error,
         %{
           severity: "error",
           source: "formatter/runtime",
           message: "Formatter bridge failed: #{inspect(reason)}",
           line: nil,
           column: nil
         }}
    end
  rescue
    error ->
      {:error,
       %{
         severity: "error",
         source: "formatter/runtime",
         message: "Formatter crashed: #{inspect(error)}",
         line: nil,
         column: nil
       }}
  end

  @spec parse_metadata_values(term()) :: term()
  defp parse_metadata_values(source) do
    metadata_source = ElmEx.Frontend.GeneratedParser.normalize_source_for_metadata(source)

    case :elm_ex_elm_lexer.string(String.to_charlist(metadata_source)) do
      {:ok, tokens, _line} ->
        parser_tokens = ElmEx.Frontend.GeneratedParser.metadata_subset_tokens(tokens)

        case :elm_ex_elm_parser.parse(parser_tokens) do
          {:ok, values} ->
            {:ok, values, tokens}

          {:error, reason} ->
            {:error,
             %{
               line: parser_error_line(reason),
               column: 1,
               message: inspect(reason)
             }}
        end

      {:error, reason, line} ->
        {:error, %{line: line, column: 1, message: inspect(reason)}}
    end
  end

  @spec valid_payload_shape?(term()) :: term()
  defp valid_payload_shape?(%{
         diagnostics: diagnostics,
         metadata: metadata,
         source_hash: source_hash
       })
       when is_list(diagnostics) and is_map(metadata) and is_integer(source_hash),
       do: true

  defp valid_payload_shape?(_), do: false

  @spec parser_error_line(term()) :: term()
  defp parser_error_line(reason) do
    case reason do
      {line, _module, _term} when is_integer(line) -> line
      {line, _term} when is_integer(line) -> line
      _ -> 1
    end
  end

  @spec unsupported_parse_reason?(term()) :: term()
  defp unsupported_parse_reason?(message) when is_binary(message) do
    String.contains?(message, "as_kw") or String.contains?(message, "newline")
  end

  @spec infer_metadata_without_parser(term()) :: term()
  defp infer_metadata_without_parser(source) do
    lines = String.split(source, "\n", trim: false)

    module_name =
      Enum.find_value(lines, fn line ->
        parse_module_name_from_line(line)
      end)

    imports =
      lines
      |> Enum.reduce([], fn line, acc ->
        case parse_import_name_from_line(line) do
          nil -> acc
          name -> [name | acc]
        end
      end)
      |> Enum.reverse()
      |> Enum.uniq()

    %{
      module: module_name,
      imports: imports,
      module_exposing: nil,
      import_entries: [],
      port_module: false,
      ports: [],
      header_lines: %{module: nil, imports: []}
    }
  end

  @spec parse_module_name_from_line(term()) :: term()
  defp parse_module_name_from_line(line) when is_binary(line) do
    trimmed = String.trim_leading(line)

    cond do
      String.starts_with?(trimmed, "module ") ->
        trimmed
        |> String.slice(7, String.length(trimmed))
        |> String.trim_leading()
        |> take_upper_path()

      String.starts_with?(trimmed, "effect module ") ->
        trimmed
        |> String.slice(14, String.length(trimmed))
        |> String.trim_leading()
        |> take_upper_path()

      String.starts_with?(trimmed, "port module ") ->
        trimmed
        |> String.slice(12, String.length(trimmed))
        |> String.trim_leading()
        |> take_upper_path()

      true ->
        nil
    end
  end

  @spec parse_import_name_from_line(term()) :: term()
  defp parse_import_name_from_line(line) when is_binary(line) do
    trimmed = String.trim_leading(line)

    if String.starts_with?(trimmed, "import ") do
      trimmed
      |> String.slice(7, String.length(trimmed))
      |> String.trim_leading()
      |> take_upper_path()
    end
  end

  @spec take_upper_path(term()) :: term()
  defp take_upper_path(rest) when is_binary(rest) do
    chars = String.graphemes(rest)
    {name_chars, _remaining} = Enum.split_while(chars, &upper_path_char?/1)
    name = Enum.join(name_chars)
    if name == "", do: nil, else: name
  end

  @spec upper_path_char?(term()) :: term()
  defp upper_path_char?(char) when is_binary(char) do
    case String.to_charlist(char) do
      [c] -> c in ?A..?Z or c in ?a..?z or c in ?0..?9 or c in [?_, ?.]
      _ -> false
    end
  end

  @spec ensure_elm_ex_modules_loaded() :: term()
  defp ensure_elm_ex_modules_loaded do
    ebin_path = Path.join([elm_ex_root(), "_build", "dev", "lib", "elm_ex", "ebin"])

    if File.dir?(ebin_path) do
      Code.append_path(String.to_charlist(ebin_path))
    end

    required_modules = [:elm_ex_elm_lexer, :elm_ex_elm_parser]
    parser_module = ElmEx.Frontend.GeneratedParser

    with nil <-
           Enum.find(required_modules, fn mod -> match?({:error, _}, Code.ensure_loaded(mod)) end),
         {:module, ^parser_module} <- Code.ensure_loaded(parser_module),
         true <- function_exported?(parser_module, :normalize_source_for_metadata, 1),
         true <- function_exported?(parser_module, :metadata_subset_tokens, 1) do
      :ok
    else
      missing when is_atom(missing) ->
        {:error, "elm_ex parser modules are not loaded (missing #{inspect(missing)})."}

      {:error, _reason} ->
        {:error, "ElmEx.Frontend.GeneratedParser is not loaded."}

      false ->
        {:error, "Loaded ElmEx.Frontend.GeneratedParser is missing metadata helpers."}
    end
  end

  @spec elm_ex_root() :: term()
  defp elm_ex_root do
    Application.get_env(:ide, Ide.Compiler, [])
    |> Keyword.fetch!(:elm_ex_root)
  end
end
