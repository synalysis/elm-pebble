defmodule Ide.Debugger.Types.AutoFireClock do
  @moduledoc false

  @typedoc "Per-surface simulated clock fields stored in `auto_fire_clock`."
  @type entry :: %{
          optional(String.t()) => integer()
        }

  @typedoc "Per-surface auto-fire clock snapshots keyed by source root (`watch`, `phone`, etc.)."
  @type t :: %{optional(String.t()) => entry()}
end
