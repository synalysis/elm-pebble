defmodule Ide.Packages.Types do
  @moduledoc """
  Shared types for package catalog search, metadata, compatibility, and docs.
  """

  @type provider_key :: atom()

  @type provider_spec :: %{
          required(:key) => provider_key(),
          required(:module) => module(),
          required(:opts) => keyword()
        }

  @type compatibility_status :: String.t()

  @type compatibility :: %{
          required(:status) => compatibility_status(),
          required(:reason_code) => String.t(),
          required(:message) => String.t()
        }

  @type package_summary :: %{
          required(:name) => String.t(),
          optional(:summary) => String.t() | nil,
          optional(:license) => String.t() | nil,
          optional(:version) => String.t() | nil
        }

  @type search_entry :: %{
          required(:name) => String.t(),
          optional(:summary) => String.t() | nil,
          optional(:license) => String.t() | nil,
          optional(:version) => String.t() | nil,
          optional(:compatibility) => compatibility()
        }

  @type package_details :: %{
          required(:name) => String.t(),
          optional(:summary) => String.t() | nil,
          optional(:license) => String.t() | nil,
          optional(:latest_version) => String.t() | nil,
          optional(:versions) => [String.t()],
          optional(:exposed_modules) => [String.t()],
          optional(:elm_json) => map(),
          optional(:source) => String.t(),
          optional(:compatibility) => compatibility()
        }

  @type search_result :: %{
          required(:source) => String.t(),
          required(:query) => String.t(),
          required(:page) => pos_integer(),
          required(:per_page) => pos_integer(),
          required(:total) => non_neg_integer(),
          required(:packages) => [search_entry()]
        }

  @type versions_result :: %{
          required(:source) => String.t(),
          required(:package) => String.t(),
          required(:versions) => [String.t()]
        }

  @type readme_result :: %{
          required(:source) => String.t(),
          required(:package) => String.t(),
          required(:version) => String.t(),
          required(:readme) => String.t()
        }

  @type doc_catalog_entry :: %{
          required(:package) => String.t(),
          required(:version) => String.t(),
          required(:modules) => [String.t()],
          required(:builtin?) => boolean(),
          required(:label) => String.t()
        }

  @type package_metadata_entry :: %{
          required(String.t()) => String.t() | [String.t()]
        }

  @type package_metadata_cache :: %{
          required(String.t()) => integer() | %{optional(String.t()) => package_metadata_entry()}
        }

  @type all_packages_map :: %{optional(String.t()) => [String.t()]}

  @type dependency_versions_map :: %{optional(String.t()) => String.t()}

  @type module_index :: %{optional(String.t()) => String.t()}

  @type catalog_opts :: keyword()

  @type catalog_http_opts :: keyword()

  @type index_cache_key :: {atom(), String.t()}

  @type docs_json_module :: %{optional(String.t()) => json_field()}

  @type json_field :: String.t() | integer() | boolean() | list() | map() | nil

  @type index_validators :: %{
          optional(:etag) => String.t(),
          optional(:last_modified) => String.t()
        }

  @type search_payload :: list() | all_packages_map()

  @type docs_cache_key :: {:docs_json, String.t(), String.t(), String.t()}

  @type dependency_constraints_map :: %{optional(String.t()) => String.t()}

  @type dependency_requirements_map :: %{optional(String.t()) => [String.t()]}

  @type dependency_assignments_map :: %{optional(String.t()) => String.t()}

  @type resolver_state :: %{
          required(:versions_cache) => %{optional(String.t()) => [String.t()]},
          required(:release_cache) => %{
            optional({String.t(), String.t()}) => dependency_constraints_map()
          }
        }

  @type resolver_error :: map()

  @type http_status_error :: {:http_status, pos_integer(), String.t()}
  @type network_error :: {:network, String.t() | map() | Exception.t()}
  @type invalid_json_error :: {:invalid_json, String.t()}

  @type catalog_error ::
          :package_not_found
          | :empty_module
          | :invalid_all_packages_payload
          | :not_modified_without_cache
          | :invalid_docs_json
          | :module_not_in_docs
          | :no_provider_available
          | invalid_json_error()
          | http_status_error()
          | network_error()

  @type elm_json_error ::
          :elm_json_not_found
          | :invalid_elm_json
          | {:invalid_elm_json, Jason.DecodeError.t() | String.t() | map()}

  @type project_package_error ::
          :builtin_package_not_removable
          | :invalid_exposed_modules
          | :not_builtin_source_backed
          | :builtin_module_docs_not_available
          | {:package_not_supported_for_phone, String.t()}
          | {:package_in_use, String.t()}
          | elm_json_error()
          | resolver_error()
          | File.posix()
          | Jason.EncodeError.t()

  @type package_error :: catalog_error() | project_package_error()

  @type watch_compat_cache_key :: {:pebble_watch_compat, 3, non_neg_integer(), String.t()}

  @type watch_compat_callbacks :: %{
          required(:versions) => (String.t() -> {:ok, [String.t()]} | {:error, package_error()}),
          required(:release) => (String.t(), String.t() -> {:ok, map()} | {:error, package_error()})
        }

  @type provider_payload ::
          [package_summary()]
          | map()
          | [String.t()]
          | String.t()
end
