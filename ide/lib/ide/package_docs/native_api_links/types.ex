defmodule Ide.PackageDocs.NativeApiLinks.Types do
  @moduledoc false

  @typedoc "Repebble docs link row with string keys `label` and `url`."
  @type api_link :: %{
          optional(:label) => String.t(),
          optional(:url) => String.t(),
          optional(String.t()) => String.t()
        }
end
