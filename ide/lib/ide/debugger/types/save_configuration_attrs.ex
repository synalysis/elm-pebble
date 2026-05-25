defmodule Ide.Debugger.Types.SaveConfigurationAttrs do
  @moduledoc """
  Configuration webview field values for `Debugger.save_configuration/2`.

  Keys are configuration field ids; values are encoded per control type at runtime.
  """

  alias Ide.Debugger.Types
  @type values_map :: %{optional(String.t()) => Types.wire_input()}

  @type t :: values_map()

  @type wire_map :: t() | map()
end
