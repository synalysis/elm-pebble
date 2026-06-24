defmodule IdeWeb.WorkspaceLive.ResourcesPage.Assigns do
  @moduledoc false

  alias Ide.Projects.Project
  alias Ide.Resources.Types, as: ResourceTypes
  alias IdeWeb.WorkspaceLive.PublishFlow
  alias IdeWeb.WorkspaceLive.ResourcesFlow

  @type resource_view :: String.t()
  @type bitmap_entry :: ResourceTypes.bitmap_entry()
  @type vector_entry :: ResourceTypes.vector_entry()
  @type animation_resource_entry :: ResourceTypes.animation_resource_entry()
  @type font_entry :: ResourceTypes.font_entry()
  @type font_source :: ResourceTypes.font_source()
  @type speaker_sample_row :: ResourcesFlow.speaker_sample_row()
  @type screenshot_group :: PublishFlow.screenshot_group()

  @type uploads :: %{optional(atom()) => Phoenix.LiveView.UploadConfig.t()}

  @type t :: %{
          optional(:pane) => atom(),
          optional(:project) => Project.t() | nil,
          optional(:resource_view) => resource_view(),
          optional(:bitmap_resources) => [bitmap_entry()],
          optional(:bitmap_resources_error) => String.t() | nil,
          optional(:vector_resources) => [vector_entry()],
          optional(:filtered_vectors) => [vector_entry()],
          optional(:animation_resources) => [animation_resource_entry()],
          optional(:font_resources) => [font_entry()],
          optional(:font_sources) => [font_source()],
          optional(:speaker_samples) => [speaker_sample_row()],
          optional(:bitmap_upload_output) => String.t() | nil,
          optional(:animation_upload_output) => String.t() | nil,
          optional(:vector_upload_output) => String.t() | nil,
          optional(:font_upload_output) => String.t() | nil,
          optional(:speaker_sample_upload_output) => String.t() | nil,
          optional(:uploads) => uploads(),
          optional(atom()) => term()
        }
end
