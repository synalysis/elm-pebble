defmodule Ide.Debugger.Types.DevicePreview do
  @moduledoc false

  alias Ide.Debugger.Types

  @typedoc "Simulator preview map for `CurrentDateTime` device responses."
  @type current_date_time :: %{
          optional(String.t()) => Types.wire_input() | Types.protocol_ctor_value()
        }

  @typedoc "Parsed firmware version triple (`major`, `minor`, `patch`)."
  @type firmware_version :: %{
          optional(String.t()) => integer()
        }
end
