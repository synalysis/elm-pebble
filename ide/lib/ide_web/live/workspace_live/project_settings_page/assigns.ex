defmodule IdeWeb.WorkspaceLive.ProjectSettingsPage.Assigns do
  @moduledoc false

  alias Ide.Auth
  alias Ide.GitHub.Repositories
  alias Ide.Projects.Project
  alias Ide.StoreAssets
  alias IdeWeb.WorkspaceLive.State

  @type settings_pane :: :settings | :settings_store | :settings_github
  @type flow_status :: :idle | :running | :ok | :error | atom()
  @type auth_mode :: Auth.auth_mode()
  @type github_repo_status :: Repositories.repo_status() | atom()
  @type project_settings_form :: State.project_settings_form()
  @type store_assets :: StoreAssets.status_map()

  @type phoenix_form :: Phoenix.HTML.Form.t()
  @type uploads :: %{optional(atom()) => Phoenix.LiveView.UploadConfig.t()}

  @type t :: %{
          optional(:pane) => settings_pane() | atom(),
          optional(:project) => Project.t() | nil,
          optional(:auth_mode) => auth_mode(),
          optional(:project_settings_form) => phoenix_form(),
          optional(:detected_capabilities) => [String.t()],
          optional(:store_listing_sync_status) => flow_status(),
          optional(:store_listing_sync_output) => String.t() | nil,
          optional(:store_assets) => store_assets(),
          optional(:github_connected?) => boolean(),
          optional(:github_repo_status) => github_repo_status(),
          optional(:github_create_status) => flow_status(),
          optional(:github_push_status) => flow_status(),
          optional(:github_push_output) => String.t() | nil,
          optional(:uploads) => uploads(),
          optional(atom()) => term()
        }
end
