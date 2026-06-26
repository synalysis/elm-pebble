defmodule Ide.Debugger.Types.ViewRenderEventPayload do
  @moduledoc "Payload for `debugger.view_render` events."
  alias Ide.Debugger.Types

  @type root :: Types.view_output_tree() | String.t() | nil

  @type t :: %{
          optional(:target) => String.t(),
          optional(:root) => root(),
          optional(String.t()) => Types.wire_input()
        }

  @spec from_render(String.t(), root()) :: t()
  def from_render(target, root) when is_binary(target), do: %{target: target, root: root}
end
