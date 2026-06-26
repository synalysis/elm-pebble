defmodule IdeWeb.CoreComponents.Assigns do
  @moduledoc false

  alias IdeWeb.Types

  @type assign_value :: Types.json_value() | Phoenix.LiveView.Rendered.t()

  @typedoc """
  Per-component `attr` fields differ; this open map documents shared Phoenix component assigns.
  """
  @type t :: %{optional(String.t()) => assign_value()}

  @type footer :: %{
          optional(:class) => String.t() | nil,
          optional(String.t()) => assign_value()
        }
end
