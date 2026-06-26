defmodule IdeWeb.WorkspaceLive.PublishPage.Assigns do
  @moduledoc false

  alias Ide.Auth
  alias Ide.PublishReadiness
  alias IdeWeb.WorkspaceLive.PublishFlow
  alias IdeWeb.WorkspaceLive.SocketAssigns

  @type flow_status :: SocketAssigns.flow_status()
  @type publish_summary :: PublishFlow.publish_summary()
  @type publish_check :: PublishReadiness.readiness_check()
  @type publish_warning :: PublishFlow.publish_warning()
  @type publish_type_guidance :: PublishFlow.publish_type_guidance()
  @type screenshot_readiness :: PublishReadiness.screenshot_readiness()
  @type release_summary :: PublishFlow.release_summary()
  @type auth_mode :: Auth.auth_mode()
  @type phoenix_form :: Phoenix.HTML.Form.t()
  @type screenshot_group :: PublishFlow.screenshot_group()
  @type t :: SocketAssigns.t()
end
