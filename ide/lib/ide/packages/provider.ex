defmodule Ide.Packages.Provider do
  @moduledoc """
  Behavior for package catalog providers.
  """

  @type package_summary :: %{
          required(:name) => String.t(),
          optional(:summary) => String.t() | nil,
          optional(:license) => String.t() | nil,
          optional(:version) => String.t() | nil
        }

  alias Ide.Packages.Types

  @callback search(String.t(), keyword()) :: {:ok, [package_summary()]} | {:error, Types.catalog_error()}
  @callback package_details(String.t(), keyword()) :: {:ok, map()} | {:error, Types.catalog_error()}
  @callback versions(String.t(), keyword()) :: {:ok, [String.t()]} | {:error, Types.catalog_error()}
  @callback package_release(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, Types.catalog_error()}
  @callback readme(String.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, Types.catalog_error()}
end
