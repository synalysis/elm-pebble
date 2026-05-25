defmodule Ide.Debugger.Types.ReloadAttrs do
  @moduledoc """
  Attributes for `Debugger.reload/2` hot-reload requests.
  """

  @type t :: %{
          optional(:rel_path) => String.t() | nil,
          optional(:reason) => String.t(),
          optional(:source) => String.t(),
          optional(:source_root) => String.t() | atom(),
          optional(String.t()) => term(),
          optional(atom()) => term()
        }

  @type wire_map :: t() | map()
end
