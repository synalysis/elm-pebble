defmodule IdeWeb.WorkspaceLive.ProjectSettingsPage.Assigns do
  @moduledoc false

  alias Ide.Auth
  alias Ide.StoreAssets
  alias IdeWeb.WorkspaceLive.ProjectSettingsFlow
  alias IdeWeb.WorkspaceLive.SocketAssigns
  alias IdeWeb.WorkspaceLive.State

  @type settings_pane :: SocketAssigns.settings_pane()
  @type flow_status :: SocketAssigns.flow_status()
  @type auth_mode :: Auth.auth_mode()
  @type github_repo_status :: SocketAssigns.github_repo_status()
  @type project_settings_form :: State.project_settings_form()
  @type pending_store_listing_sync :: ProjectSettingsFlow.pending_store_listing_sync()
  @type store_assets :: StoreAssets.status_map()
  @type phoenix_form :: Phoenix.HTML.Form.t()
  @type uploads :: IdeWeb.LiveView.Assigns.uploads()
  @type t :: SocketAssigns.t()
end
