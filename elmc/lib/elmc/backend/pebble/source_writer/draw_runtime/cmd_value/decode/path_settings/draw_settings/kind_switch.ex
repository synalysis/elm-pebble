defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue.Decode.PathSettings.DrawSettings.KindSwitch do
  @moduledoc false

  alias Elmc.Backend.Pebble.Kinds.Tables.DrawKindLuts
  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
          #{DrawKindLuts.draw_setting_kind_decode_c()}
        }

    """
  end
end
