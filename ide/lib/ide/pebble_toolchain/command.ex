defmodule Ide.PebbleToolchain.Command do
  @moduledoc false

  alias Ide.PebbleToolchain.Package

  defdelegate elm_bin(), to: Package
end
