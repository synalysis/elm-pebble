defmodule Ide.GitHub.Types do
  @moduledoc false

  @type http_body :: map() | String.t() | binary()
  @type http_error :: {:http_error, integer(), http_body()}
  @type oauth_error :: {:oauth_error, map()}
  @type git_error :: {:git_failed, String.t(), String.t()}
  @type repo_field_error :: {:missing_repo_field, String.t()} | {:invalid_repo_field, String.t()}
  @type push_rejected_error :: {:push_rejected, String.t()}
  @type repo_name_error :: {:invalid_repo_name, String.t()}
  @type unexpected_response ::
          {:unexpected_oauth_response, map()} | {:unexpected_user_response, map()}

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
