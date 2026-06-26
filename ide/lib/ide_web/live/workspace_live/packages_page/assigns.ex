defmodule IdeWeb.WorkspaceLive.PackagesPage.Assigns do
  @moduledoc false

  alias Ide.Packages.Types, as: PackageTypes
  alias IdeWeb.WorkspaceLive.EditorDependencies
  alias IdeWeb.WorkspaceLive.PackagesFlow
  alias IdeWeb.WorkspaceLive.SocketAssigns

  @type package_entry :: PackageTypes.search_entry() | PackageTypes.package_details()
  @type dependency_row :: EditorDependencies.dependency_row()
  @type search_progress :: PackagesFlow.search_progress()
  @type package_add_result :: PackageTypes.package_add_to_project_result()
  @type package_preview :: PackageTypes.package_preview_add()
  @type t :: SocketAssigns.t()
end
