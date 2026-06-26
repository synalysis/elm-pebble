defmodule Ide.Auth.Types do
  @moduledoc false

  alias Ide.Packages.Types, as: PackageTypes

  @type firebase_config :: %{
          required(:apiKey) => String.t(),
          required(:authDomain) => String.t(),
          required(:projectId) => String.t(),
          required(:storageBucket) => String.t(),
          required(:messagingSenderId) => String.t(),
          required(:appId) => String.t()
        }

  @typedoc "Firebase Identity Toolkit user record (`accounts:lookup` / sign-in payload)."
  @type firebase_user :: PackageTypes.json_wire_object()
  @type developer_profile :: PackageTypes.json_wire_object()

  @type network_error :: PackageTypes.network_error()

  @type firebase_user_error ::
          :missing_firebase_uid
          | Ecto.Changeset.t()

  @type firebase_token_error ::
          :missing_id_token
          | {:firebase_lookup_failed, pos_integer(), firebase_error_body()}
          | network_error()

  @type developer_status_error ::
          :missing_id_token
          | :unauthorized
          | :not_developer
          | {:appstore_status_failed, pos_integer(), firebase_error_body()}
          | network_error()

  @type firebase_error_body :: PackageTypes.json_wire_object() | String.t()

  @type mail_delivery_response :: PackageTypes.json_wire_object()

  @type mail_payload :: String.t() | firebase_error_body() | integer() | atom()

  @type mail_delivery_error ::
          atom()
          | String.t()
          | {:client_error, mail_payload()}
          | {:server_error, mail_payload()}
          | {:retries_exceeded, mail_payload()}
          | {:no_more_retries, mail_payload()}
end
