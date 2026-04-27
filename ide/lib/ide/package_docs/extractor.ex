defmodule Ide.PackageDocs.Extractor do
  @moduledoc false

  alias ElmEx.Frontend.DocsMetadata

  @spec build_package_docs(String.t()) :: {:ok, [map()]} | {:error, term()}
  def build_package_docs(package_root) when is_binary(package_root) do
    with {:ok, elm_json} <- read_elm_json(package_root),
         {:ok, modules} <- exposed_modules(elm_json) do
      modules
      |> Enum.reduce_while({:ok, []}, fn module_name, {:ok, acc} ->
        path = source_module_path(package_root, module_name)

        case build_module_doc(path) do
          {:ok, module_doc} -> {:cont, {:ok, [module_doc | acc]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
      |> case do
        {:ok, docs} -> {:ok, Enum.reverse(docs)}
        {:error, _} = error -> error
      end
    end
  end

  @spec read_elm_json(String.t()) :: {:ok, map()} | {:error, term()}
  def read_elm_json(package_root) when is_binary(package_root) do
    path = Path.join(package_root, "elm.json")

    with {:ok, content} <- File.read(path),
         {:ok, decoded} <- Jason.decode(content),
         true <- is_map(decoded) do
      {:ok, decoded}
    else
      {:error, reason} -> {:error, {:invalid_elm_json, path, reason}}
      false -> {:error, {:invalid_elm_json, path, :not_an_object}}
    end
  end

  @spec build_module_doc(String.t()) :: {:ok, map()} | {:error, term()}
  def build_module_doc(path) when is_binary(path) do
    with {:ok, metadata} <- apply(DocsMetadata, :parse_file, [path]),
         :ok <- validate_module_docs(metadata) do
      {:ok, metadata_to_module_doc(metadata)}
    end
  end

  @spec exposed_modules(map()) :: {:ok, [String.t()]} | {:error, term()}
  defp exposed_modules(%{"exposed-modules" => modules}) when is_list(modules) do
    {:ok, Enum.map(modules, &to_string/1)}
  end

  defp exposed_modules(%{"exposed-modules" => modules}) when is_map(modules) do
    exposed =
      modules
      |> Map.values()
      |> List.flatten()
      |> Enum.map(&to_string/1)
      |> Enum.uniq()
      |> Enum.sort()

    {:ok, exposed}
  end

  defp exposed_modules(_), do: {:error, :missing_exposed_modules}

  @spec source_module_path(String.t(), String.t()) :: String.t()
  defp source_module_path(package_root, module_name) do
    rel =
      module_name
      |> String.split(".")
      |> Path.join()
      |> Kernel.<>(".elm")

    Path.join([package_root, "src", rel])
  end

  @spec validate_module_docs(map()) :: :ok | {:error, term()}
  defp validate_module_docs(metadata) do
    docs = metadata.docs
    declarations = metadata.declarations
    exposed = exposed_declarations(metadata.module_exposing, declarations)

    cond do
      String.trim(metadata.comment) == "" ->
        {:error, {:missing_module_comment, metadata.name, metadata.path}}

      docs == [] ->
        {:error, {:missing_docs_list, metadata.name, metadata.path}}

      true ->
        with :ok <- validate_docs_references(metadata, docs, declarations, exposed),
             :ok <- validate_all_exposed_documented(metadata, docs, declarations, exposed) do
          :ok
        end
    end
  end

  @spec validate_docs_references(map(), [String.t()], map(), map()) :: :ok | {:error, term()}
  defp validate_docs_references(metadata, docs, declarations, exposed) do
    Enum.reduce_while(docs, :ok, fn doc_name, :ok ->
      name = exposed_name(doc_name)
      decl = Map.get(declarations, name)

      cond do
        is_nil(decl) ->
          {:halt, {:error, {:unknown_docs_reference, metadata.name, name, metadata.path}}}

        not Map.has_key?(exposed, name) ->
          {:halt, {:error, {:docs_reference_not_exposed, metadata.name, name, metadata.path}}}

        String.trim(decl.comment || "") == "" ->
          {:halt, {:error, {:missing_declaration_comment, metadata.name, name, metadata.path}}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  @spec validate_all_exposed_documented(map(), [String.t()], map(), map()) ::
          :ok | {:error, term()}
  defp validate_all_exposed_documented(metadata, docs, declarations, exposed) do
    documented = docs |> Enum.map(&exposed_name/1) |> MapSet.new()

    exposed
    |> Map.keys()
    |> Enum.filter(&Map.has_key?(declarations, &1))
    |> Enum.reduce_while(:ok, fn name, :ok ->
      decl = Map.fetch!(declarations, name)

      cond do
        not MapSet.member?(documented, name) ->
          {:halt,
           {:error, {:exposed_declaration_missing_from_docs, metadata.name, name, metadata.path}}}

        String.trim(decl.comment || "") == "" ->
          {:halt, {:error, {:missing_declaration_comment, metadata.name, name, metadata.path}}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  @spec metadata_to_module_doc(map()) :: map()
  defp metadata_to_module_doc(metadata) do
    exposed = exposed_declarations(metadata.module_exposing, metadata.declarations)

    initial = %{
      "name" => metadata.name,
      "comment" => metadata.comment,
      "unions" => [],
      "aliases" => [],
      "values" => [],
      "binops" => []
    }

    metadata.docs
    |> Enum.reduce(initial, fn doc_name, acc ->
      name = exposed_name(doc_name)
      declaration = Map.fetch!(metadata.declarations, name)

      case declaration.kind do
        :union ->
          cases =
            if Map.get(exposed, name) == :open do
              declaration.cases || []
            else
              []
            end

          update_in(acc["unions"], &(&1 ++ [union_doc(declaration, cases)]))

        :alias ->
          update_in(acc["aliases"], &(&1 ++ [alias_doc(declaration)]))

        :value ->
          update_in(acc["values"], &(&1 ++ [value_doc(declaration)]))
      end
    end)
  end

  @spec union_doc(map(), list()) :: map()
  defp union_doc(declaration, cases) do
    %{
      "name" => declaration.name,
      "comment" => declaration.comment,
      "args" => declaration.args || [],
      "cases" => cases
    }
  end

  @spec alias_doc(map()) :: map()
  defp alias_doc(declaration) do
    %{
      "name" => declaration.name,
      "comment" => declaration.comment,
      "args" => declaration.args || [],
      "type" => declaration.type || ""
    }
  end

  @spec value_doc(map()) :: map()
  defp value_doc(declaration) do
    %{
      "name" => declaration.name,
      "comment" => declaration.comment,
      "type" => declaration.type || ""
    }
  end

  @spec exposed_declarations(term(), map()) :: %{optional(String.t()) => :open | :opaque}
  defp exposed_declarations("..", declarations) do
    declarations
    |> Map.keys()
    |> Map.new(&{&1, :open})
  end

  defp exposed_declarations(items, _declarations) when is_list(items) do
    Map.new(items, fn item ->
      name = exposed_name(item)

      visibility =
        if String.contains?(item, "(..)") or String.contains?(item, "( .. )"),
          do: :open,
          else: :opaque

      {name, visibility}
    end)
  end

  defp exposed_declarations(_, _declarations), do: %{}

  @spec exposed_name(String.t()) :: String.t()
  defp exposed_name(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.replace(~r/\s*\(.*\)\s*$/, "")
  end
end
