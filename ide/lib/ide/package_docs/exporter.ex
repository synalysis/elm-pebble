defmodule Ide.PackageDocs.Exporter do
  @moduledoc false

  alias Ide.PackageDocs.Extractor

  @repo_root Path.expand("../../../..", __DIR__)
  @default_output Path.join(@repo_root, "elm_pebble_dev/public/package-docs")

  @type package_spec :: %{
          required(:name) => String.t(),
          required(:root) => String.t()
        }

  @spec export(keyword()) :: {:ok, map()} | {:error, term()}
  def export(opts \\ []) do
    output_root = Keyword.get(opts, :output_root, @default_output)
    packages = Keyword.get(opts, :packages, packages())

    with :ok <- reset_output_root(output_root) do
      packages
      |> Enum.reduce_while({:ok, []}, fn package, {:ok, acc} ->
        case export_package(package, output_root) do
          {:ok, result} -> {:cont, {:ok, [result | acc]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
      |> case do
        {:ok, results} ->
          {:ok,
           %{
             output_root: output_root,
             packages: Enum.reverse(results)
           }}

        {:error, _} = error ->
          error
      end
    end
  end

  @spec packages() :: [package_spec()]
  def packages do
    [
      %{name: "elm-pebble/elm-watch", root: package_root("packages/elm-pebble/elm-watch")},
      %{
        name: "elm-pebble/companion-core",
        root: package_root("packages/elm-pebble-companion-core")
      },
      %{
        name: "elm-pebble/companion-preferences",
        root: package_root("packages/elm-pebble-companion-preferences")
      }
    ]
  end

  @spec export_package(package_spec(), String.t()) :: {:ok, map()} | {:error, term()}
  defp export_package(%{name: package_name, root: package_root}, output_root) do
    with {:ok, elm_json} <- Extractor.read_elm_json(package_root),
         :ok <- validate_package_name(package_name, elm_json),
         {:ok, docs} <- Extractor.build_package_docs(package_root),
         :ok <- write_package(output_root, package_name, elm_json, docs) do
      {:ok,
       %{
         name: package_name,
         version: elm_json["version"],
         modules: Enum.map(docs, & &1["name"])
       }}
    end
  end

  @spec reset_output_root(String.t()) :: :ok | {:error, term()}
  defp reset_output_root(output_root) do
    case File.rm_rf(output_root) do
      {:ok, _} -> File.mkdir_p(output_root)
      {:error, reason, path} -> {:error, {:remove_output_failed, path, reason}}
    end
  end

  @spec write_package(String.t(), String.t(), map(), [map()]) :: :ok | {:error, term()}
  defp write_package(output_root, package_name, elm_json, docs) do
    version = elm_json["version"] || "latest"

    package_dir =
      Path.join([output_root, "packages"] ++ String.split(package_name, "/") ++ [version])

    with :ok <- File.mkdir_p(package_dir),
         :ok <- write_json(Path.join(package_dir, "elm.json"), elm_json),
         :ok <- write_json(Path.join(package_dir, "docs.json"), docs) do
      :ok
    end
  end

  @spec write_json(String.t(), term()) :: :ok | {:error, term()}
  defp write_json(path, payload) do
    json = Jason.encode!(payload, pretty: true)

    case File.write(path, json <> "\n") do
      :ok -> :ok
      {:error, reason} -> {:error, {:write_failed, path, reason}}
    end
  end

  @spec validate_package_name(String.t(), map()) :: :ok | {:error, term()}
  defp validate_package_name(expected, %{"name" => expected}), do: :ok

  defp validate_package_name(expected, %{"name" => actual}),
    do: {:error, {:package_name_mismatch, expected, actual}}

  defp validate_package_name(expected, _), do: {:error, {:package_name_mismatch, expected, nil}}

  @spec package_root(String.t()) :: String.t()
  defp package_root(relative) do
    Path.join(@repo_root, relative)
  end
end
