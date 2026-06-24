defmodule IdeWeb.WorkspaceLive.PackagesPage.Assigns do
  @moduledoc false

  alias Ide.Packages.Types, as: PackageTypes
  alias Ide.Projects.Project
  alias IdeWeb.WorkspaceLive.EditorDependencies
  alias IdeWeb.WorkspaceLive.PackagesFlow

  @type package_entry :: PackageTypes.search_entry() | PackageTypes.package_details()
  @type dependency_row :: EditorDependencies.dependency_row()
  @type search_progress :: PackagesFlow.search_progress()
  @type package_add_result :: PackageTypes.package_add_to_project_result()
  @type package_preview :: PackageTypes.package_preview_add()

  @type t :: %{
          optional(:pane) => atom(),
          optional(:project) => Project.t() | nil,
          optional(:packages_target_root) => String.t(),
          optional(:project_elm_direct) => [dependency_row()],
          optional(:project_elm_indirect) => [dependency_row()],
          optional(:packages_query) => String.t(),
          optional(:packages_search_busy) => boolean(),
          optional(:packages_search_progress) => String.t() | nil,
          optional(:packages_search_total) => non_neg_integer(),
          optional(:packages_search_results) => [package_entry()],
          optional(:packages_selected) => String.t() | nil,
          optional(:packages_details) => package_entry() | nil,
          optional(:packages_versions) => [String.t()],
          optional(:packages_preview) => package_preview() | nil,
          optional(:packages_inspect_loading) => String.t() | nil,
          optional(:packages_last_add_result) => package_add_result() | nil,
          optional(:packages_dep_docs_package) => String.t() | nil,
          optional(:packages_dep_docs_version) => String.t() | nil,
          optional(:packages_dep_readme) => String.t() | nil,
          optional(:packages_readme) => String.t() | nil,
          optional(atom()) => term()
        }
end
