defmodule Ide.Debugger.Types.ViewRenderEventPayload do
  @moduledoc "Payload for `debugger.view_render` events."

  @type root :: map() | String.t() | nil

  @type t :: %{
          optional(:target) => String.t(),
          optional(:root) => root(),
          optional(atom()) => term(),
          optional(String.t()) => term()
        }

  @spec from_render(String.t(), root()) :: t()
  def from_render(target, root) when is_binary(target), do: %{target: target, root: root}
end
