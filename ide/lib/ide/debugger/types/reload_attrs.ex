defmodule Ide.Debugger.Types.ReloadAttrs do
  @moduledoc """
  Attributes for `Debugger.reload/2` hot-reload requests.
  """

  alias Ide.Debugger.Types

  @type t :: %{
          optional(:rel_path) => String.t() | nil,
          optional(:reason) => String.t(),
          optional(:source) => String.t(),
          optional(:source_root) => String.t() | atom(),
          optional(String.t()) => Types.wire_input()
        }

  @typedoc "JSON-shaped map when atom-key `t/0` is unavailable at the wire boundary."
  @type wire_map :: t() | Types.wire_map()
end
