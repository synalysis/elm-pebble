defmodule Ide.PebbleToolchain.Package do
  @moduledoc false

  alias Ide.PebbleToolchain.Core

  defdelegate package(project_slug, opts), to: Core
  defdelegate publish(project_slug, opts), to: Core
  defdelegate infer_package_target_type(project_root, fallback), to: Core
  defdelegate template_app_root_path(), to: Core
  defdelegate deterministic_app_uuid(slug), to: Core
end
