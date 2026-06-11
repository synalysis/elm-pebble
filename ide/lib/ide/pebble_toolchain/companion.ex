defmodule Ide.PebbleToolchain.Companion do
  @moduledoc false

  alias Ide.PebbleToolchain.Package

  defdelegate companion_index_js_for_preferences(preferences_schema), to: Package
end
