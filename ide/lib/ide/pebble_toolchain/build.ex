defmodule Ide.PebbleToolchain.Build do
  @moduledoc false

  alias Ide.PebbleToolchain.Core

  defdelegate build(project_slug, opts), to: Core
end
