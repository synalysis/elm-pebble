defmodule IdeWeb.WorkspaceLive.ResourcesPage.Assigns do
  @moduledoc false

  alias Ide.Resources.Types, as: ResourceTypes
  alias IdeWeb.WorkspaceLive.PublishFlow
  alias IdeWeb.WorkspaceLive.ResourcesFlow
  alias IdeWeb.WorkspaceLive.SocketAssigns

  @type resource_view :: String.t()
  @type bitmap_entry :: ResourceTypes.bitmap_entry()
  @type vector_entry :: ResourceTypes.vector_entry()
  @type animation_resource_entry :: ResourceTypes.animation_resource_entry()
  @type font_entry :: ResourceTypes.font_entry()
  @type font_source :: ResourceTypes.font_source()
  @type speaker_sample_row :: ResourcesFlow.speaker_sample_row()
  @type screenshot_group :: PublishFlow.screenshot_group()
  @type uploads :: IdeWeb.LiveView.Assigns.uploads()
  @type t :: SocketAssigns.t()
end
