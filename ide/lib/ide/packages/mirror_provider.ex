defmodule Ide.Packages.MirrorProvider do
  @moduledoc false
  @behaviour Ide.Packages.Provider

  alias Ide.Packages.GenericProvider

  @default_base_url "https://dark.elm.dmy.fr"

  alias Ide.Packages.Types

  @impl true
  @spec search(String.t(), keyword()) ::
          {:ok, [Types.search_entry()]} | {:error, Types.catalog_error()}
  def search(query, opts), do: GenericProvider.search(query, with_defaults(opts))

  @impl true
  @spec package_details(String.t(), keyword()) ::
          {:ok, Types.package_details()} | {:error, Types.catalog_error()}
  def package_details(package, opts),
    do: GenericProvider.package_details(package, with_defaults(opts))

  @impl true
  @spec versions(String.t(), keyword()) :: {:ok, [String.t()]} | {:error, Types.catalog_error()}
  def versions(package, opts), do: GenericProvider.versions(package, with_defaults(opts))

  @impl true
  @spec readme(String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, Types.catalog_error()}
  def readme(package, version, opts),
    do: GenericProvider.readme(package, version, with_defaults(opts))

  @impl true
  @spec package_release(String.t(), String.t(), keyword()) ::
          {:ok, Types.elm_json()} | {:error, Types.catalog_error()}
  def package_release(package, version, opts),
    do: GenericProvider.package_release(package, version, with_defaults(opts))

  @spec with_defaults(keyword()) :: keyword()
  defp with_defaults(opts) do
    opts
    |> Keyword.put_new(:base_url, @default_base_url)
    |> Keyword.put_new(:cache_ttl_ms, 120_000)
  end
end
