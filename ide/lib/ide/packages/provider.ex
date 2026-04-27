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

  @callback search(String.t(), keyword()) :: {:ok, [package_summary()]} | {:error, term()}
  @callback package_details(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback versions(String.t(), keyword()) :: {:ok, [String.t()]} | {:error, term()}
  @callback package_release(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback readme(String.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
end
