defmodule Ide.GitHub.Types do
  @moduledoc false

  @type json_field :: String.t() | integer() | boolean() | [json_field()] | json_object() | nil

  @typedoc "Decoded GitHub API / OAuth JSON object (string keys)."
  @type json_object :: %{optional(String.t()) => json_field()}

  @type http_body :: json_object() | String.t() | binary()
  @type http_error :: {:http_error, integer(), http_body()}
  @type oauth_error :: {:oauth_error, json_object()}
  @type git_error :: {:git_failed, String.t(), String.t()}
  @type repo_field_error :: {:missing_repo_field, String.t()} | {:invalid_repo_field, String.t()}
  @type push_rejected_error :: {:push_rejected, String.t()}
  @type repo_name_error :: {:invalid_repo_name, String.t()}
  @type unexpected_response ::
          {:unexpected_oauth_response, json_object()}
          | {:unexpected_user_response, json_object()}

  @type connection_error :: :github_not_connected | :missing_github_user | :missing_field

  @type auth_error ::
          :oauth_client_id_missing
          | :invalid_device_code
          | :invalid_access_token
          | :invalid_device_flow_payload
          | :invalid_access_token_response
          | oauth_error()
          | unexpected_response()

  @type api_error :: http_error() | auth_error()

  @type clone_error ::
          :empty_repo_ref
          | :invalid_repo_ref
          | repo_field_error()
          | git_error()
          | connection_error()
          | File.posix()

  @type push_error ::
          git_error()
          | push_rejected_error()
          | repo_field_error()
          | connection_error()
          | File.posix()

  @type credentials_error :: File.posix() | Jason.EncodeError.t()

  @type credentials_file_values :: %{
          optional(String.t()) => String.t() | integer() | nil
        }

  @type create_repo_params :: %{
          optional(String.t()) => boolean() | String.t()
        }

  @type device_flow_payload :: %{
          optional(String.t()) => String.t() | integer() | nil
        }

  @type oauth_token_response :: json_object()

  @type user_profile :: json_object()

  @type repository :: json_object()

  @type api_json_response :: json_object()

  @type repo_ref :: %{
          required(:owner) => String.t(),
          required(:repo) => String.t(),
          required(:branch) => String.t()
        }

  @type create_repo_summary :: %{
          required(:owner) => String.t(),
          required(:repo) => String.t(),
          required(:html_url) => String.t() | nil,
          required(:private) => boolean()
        }

  @type push_snapshot_result :: %{
          required(:branch) => String.t(),
          required(:owner) => String.t(),
          required(:repo) => String.t(),
          required(:commit_sha) => String.t(),
          required(:remote_url) => String.t(),
          required(:committed) => boolean(),
          required(:history_replaced) => boolean()
        }

  @type req_transport_error ::
          Ide.Packages.Types.network_error()
          | Mint.TransportError.t()
          | String.t()
          | atom()

  @type github_error ::
          api_error()
          | clone_error()
          | push_error()
          | repo_name_error()
          | connection_error()
          | atom()
end
