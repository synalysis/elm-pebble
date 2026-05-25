defmodule Ide.Debugger.Types.SaveConfigurationAttrs do
  @moduledoc """
  Configuration webview field values for `Debugger.save_configuration/2`.

  Keys are configuration field ids; values are encoded per control type at runtime.
  """

  @type values_map :: %{optional(String.t()) => term()}

  @type t :: values_map()

  @type wire_map :: t() | map()
end
