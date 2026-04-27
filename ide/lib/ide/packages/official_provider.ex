defmodule Ide.Packages.OfficialProvider do
  @moduledoc false
  @behaviour Ide.Packages.Provider

  alias Ide.Packages.GenericProvider

  @default_base_url "https://package.elm-lang.org"

  @impl true
  @spec search(term(), term()) :: term()
  def search(query, opts), do: GenericProvider.search(query, with_defaults(opts))

  @impl true
  @spec package_details(term(), term()) :: term()
  def package_details(package, opts),
    do: GenericProvider.package_details(package, with_defaults(opts))

  @impl true
  @spec versions(term(), term()) :: term()
  def versions(package, opts), do: GenericProvider.versions(package, with_defaults(opts))

  @impl true
  @spec readme(term(), term(), term()) :: term()
  def readme(package, version, opts),
    do: GenericProvider.readme(package, version, with_defaults(opts))

  @impl true
  @spec package_release(term(), term(), term()) :: term()
  def package_release(package, version, opts),
    do: GenericProvider.package_release(package, version, with_defaults(opts))

  @spec with_defaults(term()) :: term()
  defp with_defaults(opts) do
    opts
    |> Keyword.put_new(:base_url, @default_base_url)
    |> Keyword.put_new(:cache_ttl_ms, 120_000)
  end
end
