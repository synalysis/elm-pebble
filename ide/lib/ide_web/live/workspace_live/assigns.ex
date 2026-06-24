defmodule IdeWeb.WorkspaceLive.Assigns do
  @moduledoc """
  Workspace LiveView socket assigns passed to pane `render/1` callbacks.

  Each pane also has a focused assigns module; this type documents the shared
  superset with a typed core and an open fallback for pane-specific fields.
  """

  alias Ide.Auth.User
  alias Ide.Projects.Project
  alias Ide.Settings

  @type t :: %{
          required(:pane) => atom(),
          required(:live_action) => atom(),
          optional(:project) => Project.t() | nil,
          optional(:page_title) => String.t(),
          optional(:debug_mode) => boolean(),
          optional(:companion_app_present) => boolean(),
          optional(:current_user) => User.t() | nil,
          optional(:auto_format_on_save) => boolean(),
          optional(:formatter_backend) => Settings.formatter_backend(),
          optional(atom()) => term()
        }
end
