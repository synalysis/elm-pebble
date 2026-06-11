defmodule Ide.PebbleToolchain.Build do
  @moduledoc false

  alias Ide.PebbleToolchain.Package

  defdelegate build(project_slug, opts), to: Package
end
