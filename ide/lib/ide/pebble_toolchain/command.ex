defmodule Ide.PebbleToolchain.Command do
  @moduledoc false

  alias Ide.PebbleToolchain.Core

  defdelegate elm_bin(), to: Core
end
