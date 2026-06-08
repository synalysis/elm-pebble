defmodule Ide.PebbleToolchain.Companion do
  @moduledoc false

  alias Ide.PebbleToolchain.Core

  defdelegate companion_index_js_for_preferences(preferences_schema), to: Core
end
