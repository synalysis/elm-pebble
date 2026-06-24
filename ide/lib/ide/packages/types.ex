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
          optional(:elm_json) => elm_json(),
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

  @typedoc "Decoded JSON object with string keys."
  @type json_wire_object :: %{optional(String.t()) => json_field()}

  @type json_field :: String.t() | integer() | boolean() | [json_field()] | json_wire_object() | nil

  @type http_json_body :: json_wire_object() | [json_field()]

  @type elm_json :: %{optional(String.t()) => json_field()}

  @type exposed_modules_input ::
          nil | [String.t()] | %{optional(String.t()) => String.t() | [String.t()]}

  @type index_validators :: %{
          optional(:etag) => String.t(),
          optional(:last_modified) => String.t()
        }

  @type search_wire_entry :: %{optional(String.t()) => String.t() | nil}

  @type search_payload :: [search_wire_entry()] | all_packages_map()

  @type docs_cache_key :: {:docs_json, String.t(), String.t(), String.t()}

  @type dependency_constraints_map :: %{optional(String.t()) => String.t()}

  @type dependency_requirements_map :: %{optional(String.t()) => [String.t()]}

  @type dependency_assignments_map :: %{optional(String.t()) => String.t()}

  @typedoc """
  `elm.json` `dependencies` object with optional `direct` / `indirect` version maps.
  """
  @type dependencies_section :: %{
          optional(String.t()) => dependency_versions_map() | json_field()
        }

  @type package_mutation_preview :: package_preview_add()

  @type package_preview_add :: %{
          required(:source_root) => String.t(),
          required(:rel_path) => String.t(),
          required(:package) => String.t(),
          required(:section) => String.t(),
          required(:scope) => String.t(),
          required(:selected_version) => String.t(),
          optional(:existing_constraint) => String.t() | nil,
          optional(:existing_location) => String.t() | nil,
          optional(:already_present) => boolean(),
          optional(:resolved_direct) => dependency_versions_map(),
          optional(:resolved_indirect) => dependency_versions_map()
        }

  @type package_preview_remove :: %{
          required(:source_root) => String.t(),
          required(:rel_path) => String.t(),
          required(:package) => String.t(),
          required(:section) => String.t(),
          optional(:resolved_direct) => dependency_versions_map(),
          optional(:resolved_indirect) => dependency_versions_map(),
          optional(:removed) => String.t()
        }

  @type package_dependency_diff :: %{
          required(:package) => String.t(),
          required(:section) => String.t(),
          optional(:from) => String.t() | nil,
          optional(:to) => String.t() | nil,
          optional(:scope) => String.t()
        }

  @type package_mutation_result :: %{
          required(:source_root) => String.t(),
          required(:rel_path) => String.t(),
          required(:package) => String.t(),
          required(:section) => String.t(),
          optional(:scope) => String.t(),
          optional(:selected_version) => String.t(),
          optional(:existing_constraint) => String.t() | nil,
          optional(:existing_location) => String.t() | nil,
          optional(:already_present) => boolean(),
          optional(:resolved_direct) => dependency_versions_map(),
          optional(:resolved_indirect) => dependency_versions_map(),
          optional(:removed) => String.t(),
          optional(:changed) => boolean(),
          optional(:previous_version) => String.t() | nil,
          optional(:dependency_diff) => package_dependency_diff()
        }

  @type package_add_to_project_result :: %{
          required(:source_root) => String.t(),
          required(:rel_path) => String.t(),
          required(:package) => String.t(),
          required(:section) => String.t(),
          required(:project) => Ide.Projects.Project.t(),
          optional(:scope) => String.t(),
          optional(:selected_version) => String.t(),
          optional(:existing_constraint) => String.t() | nil,
          optional(:existing_location) => String.t() | nil,
          optional(:already_present) => boolean(),
          optional(:resolved_direct) => dependency_versions_map(),
          optional(:resolved_indirect) => dependency_versions_map(),
          optional(:changed) => boolean(),
          optional(:previous_version) => String.t() | nil,
          optional(:dependency_diff) => package_dependency_diff()
        }

  @type catalog_entry_with_compat :: search_entry() | package_details()

  @type resolver_not_direct_error :: %{
          required(:kind) => :not_direct_dependency,
          required(:package) => String.t()
        }

  @type resolver_no_compatible_version_error :: %{
          required(:kind) => :no_compatible_version,
          required(:package) => String.t(),
          optional(:constraints) => [String.t()]
        }

  @type resolver_versions_unavailable_error :: %{
          required(:kind) => :versions_unavailable,
          required(:package) => String.t(),
          required(:reason) => package_error()
        }

  @type resolver_resolution_failed_error :: %{
          required(:kind) => :resolution_failed,
          required(:reason) => resolver_error() | atom() | String.t()
        }

  @type resolver_error ::
          resolver_not_direct_error()
          | resolver_no_compatible_version_error()
          | resolver_versions_unavailable_error()
          | resolver_resolution_failed_error()

  @type provider_payload ::
          [search_entry()]
          | package_details()
          | elm_json()
          | search_payload()
          | [String.t()]
          | String.t()

  @type resolver_state :: %{
          required(:versions_cache) => %{optional(String.t()) => [String.t()]},
          required(:release_cache) => %{
            optional({String.t(), String.t()}) => dependency_constraints_map()
          }
        }

  @type http_status_error :: {:http_status, pos_integer(), String.t()}
  @type http_error_detail :: String.t() | json_wire_object() | Exception.t()
  @type network_error :: {:network, http_error_detail()}
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
          | {:invalid_elm_json, Jason.DecodeError.t() | String.t() | json_wire_object()}

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

  @type versions_fetcher :: (String.t() -> {:ok, [String.t()]} | {:error, package_error()})

  @type release_fetcher ::
          (String.t(), String.t() -> {:ok, elm_json()} | {:error, package_error()})

  @type watch_compat_callbacks :: %{
          required(:versions) => versions_fetcher(),
          required(:release) => release_fetcher()
        }

  @type resolve_result :: %{
          required(:direct) => dependency_versions_map(),
          required(:indirect) => dependency_versions_map(),
          required(:selected_version) => String.t() | nil,
          optional(:assignments) => dependency_assignments_map()
        }

  @type resolve_after_remove_result :: %{
          required(:direct) => dependency_versions_map(),
          required(:indirect) => dependency_versions_map(),
          required(:removed) => String.t(),
          optional(:assignments) => dependency_assignments_map()
        }

  @type elm_json_editor_opts :: [
          versions_fetcher: versions_fetcher(),
          release_fetcher: release_fetcher(),
          source_root: String.t() | nil,
          section: String.t() | nil,
          scope: String.t() | nil
        ]

end
