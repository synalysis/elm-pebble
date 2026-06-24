defmodule Ide.AppStore do
  @moduledoc """
  Small client for public Rebble app store metadata.
  """

  alias Ide.Packages.Http
  alias Ide.Packages.Types
  alias Ide.AppStore.Types, as: AppStoreTypes

  @spec fetch_app_by_id(String.t(), keyword()) ::
          {:ok, AppStoreTypes.json_object()} | {:error, AppStoreTypes.fetch_app_error()}
  def fetch_app_by_id(app_id, opts \\ []) when is_binary(app_id) do
    app_id = String.trim(app_id)
    hardware = Keyword.get(opts, :hardware, "basalt")

    path = "/api/v1/apps/id/#{URI.encode(app_id)}?hardware=#{URI.encode(hardware)}"

    with {:ok, decoded} <- Http.get_json(path, http_opts(opts)),
         {:ok, app} <- extract_single_app(decoded) do
      {:ok, app}
    end
  end

  @spec http_opts(keyword()) :: Types.catalog_http_opts()
  defp http_opts(opts) do
    [
      base_url: Keyword.get(opts, :base_url, base_url()),
      timeout_ms: Keyword.get(opts, :timeout_ms, 8_000),
      accept: "application/json"
    ]
  end

  @spec base_url() :: String.t()
  defp base_url do
    Application.get_env(:ide, Ide.AppStore, [])
    |> Keyword.get(:base_url, "https://appstore-api.repebble.com")
  end

  @spec extract_single_app(AppStoreTypes.json_object()) ::
          {:ok, AppStoreTypes.json_object()} | {:error, :app_not_found | :invalid_appstore_response}
  defp extract_single_app(%{"data" => [%{} = app | _]}), do: {:ok, app}
  defp extract_single_app(%{"data" => []}), do: {:error, :app_not_found}
  defp extract_single_app(_), do: {:error, :invalid_appstore_response}
end
