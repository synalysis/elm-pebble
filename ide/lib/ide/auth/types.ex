defmodule Ide.Auth.Types do
  @moduledoc false

  alias Ide.Packages.Types, as: PackageTypes

  @type firebase_user :: map()
  @type developer_profile :: map()

  @type network_error :: PackageTypes.network_error()

  @type firebase_user_error ::
          :missing_firebase_uid
          | Ecto.Changeset.t()

  @type firebase_token_error ::
          :missing_id_token
          | {:firebase_lookup_failed, pos_integer(), map() | String.t()}
          | network_error()

  @type developer_status_error ::
          :missing_id_token
          | :unauthorized
          | :not_developer
          | {:appstore_status_failed, pos_integer(), map() | String.t()}
          | network_error()

  @type mail_delivery_response :: map()

  @type mail_payload :: String.t() | map() | integer() | atom()

  @type mail_delivery_error ::
          atom()
          | String.t()
          | {:client_error, mail_payload()}
          | {:server_error, mail_payload()}
          | {:retries_exceeded, mail_payload()}
          | {:no_more_retries, mail_payload()}
end
