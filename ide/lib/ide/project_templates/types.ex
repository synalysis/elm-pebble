defmodule Ide.ProjectTemplates.Types do
  @moduledoc false

  alias Ide.Packages.Types, as: PackageTypes
  alias Ide.Projects.Types, as: ProjectsTypes

  @type template_metadata :: %{
          optional(String.t()) => [String.t()] | String.t() | boolean() | nil
        }

  @type release_defaults :: ProjectsTypes.release_defaults()
  @type elm_json :: PackageTypes.elm_json()
  @type dependency_map :: PackageTypes.dependency_versions_map()

  @type picker_entry :: %{
          required(:key) => String.t(),
          required(:title) => String.t(),
          optional(:description) => String.t() | nil,
          required(:target_type) => String.t(),
          required(:has_companion) => boolean(),
          optional(:screenshot_url) => String.t() | nil
        }

  @type catalog_entry :: %{
          required(:key) => String.t(),
          required(:label) => String.t(),
          required(:target_type) => String.t(),
          required(:has_companion) => boolean()
        }

  @type picker_category :: %{
          required(:id) => String.t(),
          required(:label) => String.t(),
          required(:templates) => [picker_entry()]
        }
end
