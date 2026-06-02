defmodule Ide.PackageDocs.Exporter do
  @moduledoc false

  alias Ide.PackageDocs.Extractor
  alias Ide.PackageDocs.Types

  @repo_root Path.expand("../../../..", __DIR__)
  @default_output Path.join(@repo_root, "elm_pebble_dev/public/package-docs")

  @type package_spec :: %{
          required(:name) => String.t(),
          required(:root) => String.t()
        }

  @spec export(keyword()) :: {:ok, map()} | {:error, Types.export_error()}
  def export(opts \\ []) do
    output_root = Keyword.get(opts, :output_root, @default_output)
    packages = Keyword.get(opts, :packages, packages())
    staging_root = staging_output_root(output_root)

    with :ok <- reset_output_root(staging_root),
         {:ok, results} <- export_packages(packages, staging_root),
         :ok <- promote_output_root(staging_root, output_root) do
      {:ok, %{output_root: output_root, packages: results}}
    else
      {:error, _} = error ->
        File.rm_rf(staging_root)
        error
    end
  end

  @spec export_packages([package_spec()], String.t()) ::
          {:ok, [map()]} | {:error, Types.export_error()}
  defp export_packages(packages, output_root) do
    packages
    |> Enum.reduce_while({:ok, []}, fn package, {:ok, acc} ->
      case export_package(package, output_root) do
        {:ok, result} -> {:cont, {:ok, [result | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      {:error, _} = error -> error
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

  @spec export_package(package_spec(), String.t()) ::
          {:ok, map()} | {:error, Types.export_error()}
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

  @spec reset_output_root(String.t()) :: :ok | {:error, Types.export_error()}
  defp reset_output_root(output_root) do
    case File.rm_rf(output_root) do
      {:ok, _} -> File.mkdir_p(output_root)
      {:error, reason, path} -> {:error, {:remove_output_failed, path, reason}}
    end
  end

  @spec staging_output_root(String.t()) :: String.t()
  defp staging_output_root(output_root) when is_binary(output_root) do
    output_root <> ".staging-" <> Integer.to_string(System.unique_integer([:positive]))
  end

  @spec promote_output_root(String.t(), String.t()) :: :ok | {:error, Types.export_error()}
  defp promote_output_root(staging_root, output_root)
       when is_binary(staging_root) and is_binary(output_root) do
    backup_root =
      output_root <> ".backup-" <> Integer.to_string(System.unique_integer([:positive]))

    with :ok <- move_path(staging_root, output_root, backup_root),
         :ok <- cleanup_backup(backup_root) do
      :ok
    else
      {:error, _} = error ->
        _ = restore_backup(backup_root, output_root)
        _ = File.rm_rf(staging_root)
        error
    end
  end

  @spec move_path(String.t(), String.t(), String.t()) :: :ok | {:error, Types.export_error()}
  defp move_path(from, to, backup_root) do
    cond do
      File.exists?(to) ->
        with :ok <- rename_path(to, backup_root),
             :ok <- rename_path(from, to) do
          :ok
        end

      true ->
        rename_path(from, to)
    end
  end

  @spec rename_path(String.t(), String.t()) :: :ok | {:error, Types.export_error()}
  defp rename_path(from, to) do
    case File.rename(from, to) do
      :ok -> :ok
      {:error, reason} -> {:error, {:rename_output_failed, from, to, reason}}
    end
  end

  @spec cleanup_backup(String.t()) :: :ok
  defp cleanup_backup(backup_root) when is_binary(backup_root) do
    case File.rm_rf(backup_root) do
      {:ok, _} -> :ok
      _ -> :ok
    end
  end

  @spec restore_backup(String.t(), String.t()) :: :ok
  defp restore_backup(backup_root, output_root) do
    if File.exists?(backup_root) do
      _ = File.rm_rf(output_root)
      _ = File.rename(backup_root, output_root)
    end

    :ok
  end

  @spec write_package(String.t(), String.t(), map(), [map()]) ::
          :ok | {:error, Types.export_error()}
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

  @spec write_json(String.t(), map() | [map()]) :: :ok | {:error, Types.export_error()}
  defp write_json(path, payload) do
    json = Jason.encode!(payload, pretty: true)

    case File.write(path, json <> "\n") do
      :ok -> :ok
      {:error, reason} -> {:error, {:write_failed, path, reason}}
    end
  end

  @spec validate_package_name(String.t(), map()) :: :ok | {:error, Types.export_error()}
  defp validate_package_name(expected, %{"name" => expected}), do: :ok

  defp validate_package_name(expected, %{"name" => actual}),
    do: {:error, {:package_name_mismatch, expected, actual}}

  defp validate_package_name(expected, _), do: {:error, {:package_name_mismatch, expected, nil}}

  @spec package_root(String.t()) :: String.t()
  defp package_root(relative) do
    Path.join(@repo_root, relative)
  end
end
