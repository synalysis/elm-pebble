defmodule IdeWeb.WorkspaceLive.EmulatorPage.Assigns do
  @moduledoc false

  alias Ide.Emulator.Types, as: EmulatorTypes
  alias IdeWeb.WorkspaceLive.PublishFlow
  alias IdeWeb.WorkspaceLive.SocketAssigns

  @type flow_status :: SocketAssigns.flow_status()
  @type installation_status :: EmulatorTypes.installation_status()
  @type phoenix_form :: Phoenix.HTML.Form.t()
  @type screenshot_group :: PublishFlow.screenshot_group()
  @type t :: SocketAssigns.t()
end
