defmodule IdeWeb.ProjectsLive.Assigns do
  @moduledoc false

  alias Ide.Auth.User
  alias Ide.ProjectTemplates.Types, as: TemplateTypes
  alias Ide.Projects.Project
  alias Ide.Projects.Types, as: ProjectTypes

  @type import_mode :: :local | :github
  @type project_attrs :: ProjectTypes.project_attrs()
  @type phoenix_form :: Phoenix.HTML.Form.t()

  @type t :: %{
          optional(:page_title) => String.t(),
          optional(:current_user) => User.t() | nil,
          optional(:projects) => [Project.t()],
          optional(:template_categories) => [TemplateTypes.picker_category()],
          optional(:template_target_filter) => String.t(),
          optional(:template_companion_filter) => String.t(),
          optional(:show_create_modal) => boolean(),
          optional(:selected_template) => String.t(),
          optional(:create_name_user_edited) => boolean(),
          optional(:form) => phoenix_form(),
          optional(:show_import_form) => boolean(),
          optional(:import_mode) => import_mode(),
          optional(:github_connected?) => boolean(),
          optional(:import_form) => phoenix_form(),
          optional(:github_import_form) => phoenix_form(),
          optional(atom()) => term()
        }
end
