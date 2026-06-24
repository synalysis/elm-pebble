defmodule Ide.AppStore.Types do
  @moduledoc """
  Types for App Store publish options and API context.
  """

  alias Ide.Packages.Types, as: PackageTypes
  alias Ide.Projects.Project
  alias Ide.Projects.Types, as: ProjectsTypes
  alias Ide.ZipArchive

  @type json_field :: String.t() | integer() | boolean() | [json_field()] | json_object() | nil

  @typedoc "Decoded App Store / PBW JSON object (string keys)."
  @type json_object :: %{optional(String.t()) => json_field()}

  @type http_body :: json_object() | String.t() | binary() | nil
  @type http_response :: json_object() | String.t() | binary()

  @type publish_project :: Project.t() | ProjectsTypes.release_defaults_carrier()

  @type multipart_form_fields :: %{optional(String.t()) => String.t() | nil}

  @type store_icons :: %{optional(String.t()) => String.t()}

  @type zip_manifest_json :: json_object()

  @type pebble_watchapp_json :: %{
          optional(String.t()) => boolean() | String.t() | integer()
        }

  @type publish_opts :: [
          {:app_root, String.t()}
          | {:artifact_path, String.t()}
          | {:api_base, String.t()}
          | {:firebase_id_token, String.t()}
          | {:release_notes, String.t()}
          | {:version, String.t()}
          | {:description, String.t()}
          | {:screenshots, [String.t()]}
          | {:is_published, boolean()}
          | {:visibility, Ide.AppStore.PublishFlags.visibility()}
          | {:all_platforms, boolean()}
          | {:gif_all_platforms, boolean()}
          | {:store_icons, store_icons()}
          | {:generate_store_graphics, boolean()}
          | {:website, String.t()}
          | {:source, String.t()}
          | {:request_fun,
             (atom(), String.t(), list(), http_body(), pos_integer() -> http_response())}
          | keyword()
        ]

  @type pbw_metadata :: %{
          required(:app_uuid) => String.t(),
          required(:app_name) => String.t(),
          required(:version) => String.t(),
          required(:platforms) => [String.t()],
          required(:app_type) => String.t()
        }

  @type publish_context :: %{
          required(:api_base) => String.t(),
          required(:token) => String.t(),
          required(:artifact_path) => String.t(),
          required(:release_notes) => String.t(),
          required(:screenshots) => [String.t()],
          required(:version) => String.t(),
          required(:description) => String.t(),
          required(:visibility) => Ide.AppStore.PublishFlags.visibility(),
          required(:is_published) => boolean(),
          required(:metadata) => pbw_metadata(),
          required(:opts) => publish_opts()
        }

  @type developer_me :: json_object()

  @type api_payload :: json_object()

  @type api_status_error :: {pos_integer(), api_payload()}

  @type network_error :: PackageTypes.network_error()

  @type developer_error ::
          :developer_not_linked
          | String.t()

  @type upload_label_error :: String.t()

  @type multipart_error ::
          {:file_not_found, String.t()}
          | api_status_error()
          | network_error()

  @type zip_json_error ::
          :invalid_json_object
          | Jason.DecodeError.t()
          | ZipArchive.zip_error()

  @type pbw_prepare_error :: zip_json_error() | File.posix()

  @type publish_flow_error ::
          developer_error()
          | upload_label_error()
          | multipart_error()
          | zip_json_error()
          | String.t()

  @type publish_rescue_error :: Exception.t()

  @type publish_error ::
          :invalid_project
          | publish_flow_error()
          | publish_rescue_error()

  @type listing_atom_error ::
          :firebase_token_required
          | :developer_not_linked
          | :package_json_invalid
          | :app_uuid_required

  @type listing_error ::
          listing_atom_error()
          | String.t()
          | api_status_error()
          | network_error()

  @type fetch_app_error ::
          PackageTypes.catalog_error()
          | :app_not_found
          | :invalid_appstore_response
end
