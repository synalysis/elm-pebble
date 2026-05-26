defmodule Ide.Mcp.Handlers.Packages do
  @moduledoc false

  alias Ide.Mcp.ToolSupport
  alias Ide.Mcp.ToolTypes
  alias Ide.Packages

  def call("packages.search", args) do
    query = Map.get(args, "query", "")
    platform_target = parse_platform_target(Map.get(args, "platform_target"))

    opts =
      []
      |> ToolSupport.put_opt(:page, Map.get(args, "page"))
      |> ToolSupport.put_opt(:per_page, Map.get(args, "per_page"))
      |> ToolSupport.put_opt(:platform_target, platform_target)

    case Packages.search(query, opts) do
      {:ok, payload} -> {:ok, payload}
      {:error, reason} -> {:error, "packages search failed: #{inspect(reason)}"}
    end
  end

  def call("packages.details", %{"package" => package}) do
    case Packages.package_details(package, []) do
      {:ok, payload} -> {:ok, payload}
      {:error, reason} -> {:error, "packages details failed: #{inspect(reason)}"}
    end
  end

  def call("packages.versions", %{"package" => package}) do
    case Packages.versions(package, []) do
      {:ok, payload} -> {:ok, payload}
      {:error, reason} -> {:error, "packages versions failed: #{inspect(reason)}"}
    end
  end

  def call("packages.readme", %{"package" => package} = args) do
    version = Map.get(args, "version", "latest")

    case Packages.readme(package, version, []) do
      {:ok, payload} -> {:ok, payload}
      {:error, reason} -> {:error, "packages readme failed: #{inspect(reason)}"}
    end
  end

  def call("packages.module_docs", %{"package" => package, "module" => module_name} = args) do
    version = Map.get(args, "version", "latest")

    case Packages.module_doc_markdown(package, version, module_name, []) do
      {:ok, markdown} ->
        {:ok, packages_module_docs_payload(package, version, module_name, markdown)}

      {:error, reason} ->
        {:error, "packages module docs failed: #{inspect(reason)}"}
    end
  end

  def call("packages.add_to_elm_json", %{"slug" => slug, "package" => package} = args) do
    opts =
      []
      |> ToolSupport.put_opt(:source_root, Map.get(args, "source_root"))
      |> ToolSupport.put_opt(:section, Map.get(args, "section"))
      |> ToolSupport.put_opt(:scope, Map.get(args, "scope"))

    with {:ok, project} <- ToolSupport.fetch_project(slug),
         {:ok, result} <- Packages.add_to_project(project, package, opts) do
      {:ok, Map.put(result, :slug, slug)}
    else
      {:error, reason} -> {:error, "packages add failed: #{inspect(reason)}"}
    end
  end

  def call("packages.remove_from_elm_json", %{"slug" => slug, "package" => package} = args) do
    opts =
      []
      |> ToolSupport.put_opt(:source_root, Map.get(args, "source_root"))
      |> ToolSupport.put_opt(:section, Map.get(args, "section"))

    with {:ok, project} <- ToolSupport.fetch_project(slug),
         {:ok, result} <- Packages.remove_from_project(project, package, opts) do
      {:ok, Map.put(result, :slug, slug)}
    else
      {:error, reason} -> {:error, "packages remove failed: #{inspect(reason)}"}
    end
  end

  @spec packages_module_docs_payload(String.t(), String.t(), String.t(), String.t()) ::
          ToolTypes.packages_module_docs_result()
  defp packages_module_docs_payload(package, version, module_name, markdown)
       when is_binary(package) and is_binary(version) and is_binary(module_name) and
              is_binary(markdown) do
    %{package: package, version: version, module: module_name, markdown: markdown}
  end

  @spec parse_platform_target(String.t() | atom() | nil) :: :watch | :phone | nil
  defp parse_platform_target("watch"), do: :watch
  defp parse_platform_target("phone"), do: :phone
  defp parse_platform_target(_), do: nil
end
