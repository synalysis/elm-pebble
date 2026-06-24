defmodule IdeWeb.WorkspaceLive.PublishPage.Assigns do
  @moduledoc false

  alias Ide.Auth
  alias Ide.PublishReadiness
  alias Ide.Projects.Project
  alias Ide.Screenshots
  alias IdeWeb.WorkspaceLive.PublishFlow

  @type flow_status :: :idle | :running | :ok | :error | atom()
  @type publish_summary :: PublishFlow.publish_summary()
  @type publish_check :: PublishReadiness.readiness_check()
  @type publish_warning :: PublishFlow.publish_warning()
  @type publish_type_guidance :: PublishFlow.publish_type_guidance()
  @type screenshot_readiness :: PublishReadiness.screenshot_readiness()
  @type release_summary :: PublishFlow.release_summary()
  @type auth_mode :: Auth.auth_mode()

  @type phoenix_form :: Phoenix.HTML.Form.t()
  @type screenshot_group :: PublishFlow.screenshot_group()

  @type t :: %{
          optional(:pane) => atom(),
          optional(:project) => Project.t() | nil,
          optional(:auth_mode) => auth_mode(),
          optional(:prepare_release_status) => flow_status(),
          optional(:prepare_release_output) => String.t() | nil,
          optional(:publish_summary) => publish_summary(),
          optional(:publish_checks) => [publish_check()],
          optional(:publish_warnings) => [publish_warning()],
          optional(:publish_type_guidance) => publish_type_guidance(),
          optional(:publish_readiness) => [screenshot_readiness()],
          optional(:publish_artifact_path) => String.t() | nil,
          optional(:manifest_export_path) => String.t() | nil,
          optional(:release_notes_path) => String.t() | nil,
          optional(:release_summary) => release_summary(),
          optional(:release_summary_form) => phoenix_form(),
          optional(:publish_submit_options) => PublishFlow.publish_submit_option_map(),
          optional(:screenshots) => [Screenshots.screenshot()],
          optional(:screenshot_groups) => [screenshot_group()],
          optional(atom()) => term()
        }
end
