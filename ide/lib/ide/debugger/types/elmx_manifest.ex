defmodule Ide.Debugger.Types.ElmxManifest do
  @moduledoc false

  alias Ide.Debugger.Types

  @typedoc """
  `elmx_manifest.json` attached to compiled watch surfaces (`contract`, `entry_module`, etc.).
  """
  @type t :: %{
          optional(String.t()) => Types.wire_scalar() | String.t()
        }

  @typedoc "String-key JSON map when atom-key `t/0` is unavailable at the wire boundary."
  @type wire_map :: t() | Types.wire_string_map()
end
