defmodule Ide.EditorDocLinks do
  @moduledoc false

  alias Ide.Debugger.CompileContract
  alias ElmEx.DebuggerContract.Types, as: DebuggerContractTypes

  @type import_entry :: DebuggerContractTypes.import_entry()
  @type resolve_symbol_result ::
          {:ok, String.t(), String.t()} | {:error, :bad_qualified_word | :not_in_exposing}

  @type resolve_error ::
          :no_import_metadata | :unresolved_symbol | :bad_qualified_word | :not_in_exposing

  @doc """
  Given editor `content` and a byte `offset`, resolves a documentation URL on package.elm-lang.org
  when the identifier refers to an imported module symbol and `module_index` maps module names to packages.
  """
  @spec resolve(String.t(), non_neg_integer(), %{optional(String.t()) => String.t()}) ::
          {:ok, %{url: String.t(), package: String.t(), module: String.t(), symbol: String.t()}}
          | {:error, resolve_error()}
  def resolve(content, offset, module_index)
      when is_binary(content) and is_integer(offset) and is_map(module_index) do
    with {:ok, snapshot} <- CompileContract.analyze_source(content, "Editor.elm"),
         {:ok, imports} <- import_entries_from_snapshot(snapshot),
         {:ok, word} <- word_from_offset(content, offset),
         {:ok, module_name, symbol} <- resolve_module_for_word(word, imports),
         {:ok, package} <- Map.fetch(module_index, module_name) do
      {:ok,
       %{
         package: package,
         module: module_name,
         symbol: symbol,
         url: package_elm_doc_url(package, module_name, symbol)
       }}
    else
      {:error, _} = err -> err
      :error -> {:error, :unresolved_symbol}
    end
  end

  @spec import_entries_from_snapshot(map()) ::
          {:ok, [import_entry()]} | {:error, :no_import_metadata}
  defp import_entries_from_snapshot(%{"debugger_contract" => %{"import_entries" => imports}})
       when is_list(imports),
       do: {:ok, imports}

  defp import_entries_from_snapshot(%{"elm_introspect" => %{"import_entries" => imports}})
       when is_list(imports),
       do: {:ok, imports}

  defp import_entries_from_snapshot(_), do: {:error, :no_import_metadata}

  @spec word_from_offset(String.t(), non_neg_integer()) :: {:ok, String.t()} | :error
  defp word_from_offset(content, offset) do
    case word_at_offset(content, offset) do
      "" -> :error
      w -> {:ok, w}
    end
  end

  @spec package_elm_doc_url(String.t(), String.t(), String.t()) :: String.t()
  def package_elm_doc_url(package, module_name, symbol)
      when is_binary(package) and is_binary(module_name) and is_binary(symbol) do
    path_mod = module_name |> String.replace(".", "-")
    frag = uri_fragment(symbol)
    "https://package.elm-lang.org/packages/#{package}/latest/#{path_mod}#{frag}"
  end

  @spec uri_fragment(String.t()) :: String.t()
  defp uri_fragment(""), do: ""

  defp uri_fragment(sym) do
    if Regex.match?(~r/^[A-Za-z0-9_]+$/, sym),
      do: "#" <> sym,
      else: "#" <> URI.encode_www_form(sym)
  end

  @spec word_at_offset(String.t(), non_neg_integer()) :: String.t()
  defp word_at_offset(content, offset) do
    len = byte_size(content)
    offset = min(max(offset, 0), len)
    {before, after_at} = split_at_byte(content, offset)

    left =
      case Regex.run(~r/[A-Za-z0-9_.]*$/, before) do
        [m] -> m
        _ -> ""
      end

    right =
      case Regex.run(~r/^[A-Za-z0-9_.]*/, after_at) do
        [m] -> m
        _ -> ""
      end

    left <> right
  end

  @spec split_at_byte(String.t(), non_neg_integer()) :: {String.t(), String.t()}
  defp split_at_byte(content, offset) do
    before = binary_part(content, 0, offset)
    after_len = byte_size(content) - offset
    after_at = if after_len > 0, do: binary_part(content, offset, after_len), else: ""
    {before, after_at}
  end

  @spec resolve_module_for_word(String.t(), [import_entry()]) :: resolve_symbol_result()
  defp resolve_module_for_word(word, imports) do
    alias_map = import_alias_map(imports)

    cond do
      String.contains?(word, ".") ->
        segments = String.split(word, ".")
        symbol = List.last(segments)
        ref = segments |> Enum.drop(-1) |> Enum.join(".")

        module_name =
          case Map.get(alias_map, ref) do
            nil -> ref
            full -> full
          end

        if module_name != "" and symbol != "" do
          {:ok, module_name, symbol}
        else
          {:error, :bad_qualified_word}
        end

      true ->
        case find_import_for_unqualified(word, imports) do
          nil -> {:error, :not_in_exposing}
          mod -> {:ok, mod, word}
        end
    end
  end

  @spec import_alias_map([import_entry()]) :: %{optional(String.t()) => String.t()}
  defp import_alias_map(imports) do
    Enum.reduce(imports, %{}, fn entry, acc ->
      mod = Map.get(entry, "module") || Map.get(entry, :module)
      as_name = Map.get(entry, "as") || Map.get(entry, :as)

      if is_binary(mod) and mod != "" do
        acc = Map.put(acc, mod, mod)
        if is_binary(as_name) and as_name != "", do: Map.put(acc, as_name, mod), else: acc
      else
        acc
      end
    end)
  end

  @spec find_import_for_unqualified(String.t(), [import_entry()]) :: String.t() | nil
  defp find_import_for_unqualified(word, imports) do
    Enum.find_value(imports, fn entry ->
      mod = Map.get(entry, "module") || Map.get(entry, :module)
      exposing = Map.get(entry, "exposing") || Map.get(entry, :exposing)

      cond do
        not is_binary(mod) or mod == "" ->
          nil

        exposing == ".." ->
          mod

        is_list(exposing) and word in exposing ->
          mod

        true ->
          nil
      end
    end)
  end
end
