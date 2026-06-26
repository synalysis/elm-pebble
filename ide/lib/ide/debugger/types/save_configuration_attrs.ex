defmodule Ide.Debugger.Types.SaveConfigurationAttrs do
  @moduledoc """
  Configuration webview field values for `Debugger.save_configuration/2`.

  Keys are configuration field ids; values are encoded per control type at runtime.
  """

  alias Ide.Debugger.Types
  @type values_map :: %{optional(String.t()) => Types.wire_input()}

  @type t :: values_map()

  @typedoc "JSON-shaped map when atom-key `t/0` is unavailable at the wire boundary."
  @type wire_map :: t() | Types.wire_map()
end
