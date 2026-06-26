defmodule IdeWeb.LiveView.Assigns do
  @moduledoc """
  Shared Phoenix LiveView socket assign fragments reused across IDE LiveViews.
  """

  alias Ide.Auth
  alias Ide.Auth.Types, as: AuthTypes
  alias Ide.Auth.User

  @typedoc "Phoenix flash messages (`put_flash/3` uses atom keys such as `:info` and `:error`)."
  @type flash :: %{
          optional(:info) => String.t(),
          optional(:error) => String.t(),
          optional(:warning) => String.t(),
          optional(String.t()) => String.t()
        }

  @typedoc "Workspace LiveView uploads registered in mount via `allow_upload/3`."
  @type workspace_uploads :: %{
          optional(:bitmap) => Phoenix.LiveView.UploadConfig.t(),
          optional(:animation) => Phoenix.LiveView.UploadConfig.t(),
          optional(:vector) => Phoenix.LiveView.UploadConfig.t(),
          optional(:font) => Phoenix.LiveView.UploadConfig.t(),
          optional(:speaker_sample) => Phoenix.LiveView.UploadConfig.t(),
          optional(:store_icon_small) => Phoenix.LiveView.UploadConfig.t(),
          optional(:store_icon_large) => Phoenix.LiveView.UploadConfig.t()
        }

  @type uploads :: workspace_uploads()

  @type auth_assigns :: %{
          optional(:auth_mode) => Auth.auth_mode(),
          optional(:current_user) => User.t() | nil,
          optional(:firebase_id_token) => String.t() | nil,
          optional(:firebase_id_token_exp) => integer() | nil,
          optional(:firebase_config) => AuthTypes.firebase_config()
        }

  @type layout_assigns :: %{
          optional(:flash) => flash(),
          optional(:page_title) => String.t(),
          optional(:live_action) => atom()
        }
end
