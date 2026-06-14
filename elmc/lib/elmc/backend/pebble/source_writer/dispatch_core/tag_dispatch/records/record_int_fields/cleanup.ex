defmodule Elmc.Backend.Pebble.SourceWriter.DispatchCore.TagDispatch.Records.RecordIntFields.Cleanup do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
        cleanup_values:
          for (int i = 0; i < built; i++) {
            if (record_values[i]) elmc_release(record_values[i]);
          }
          free(record_values);
          elmc_release(tag_value);
          ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_record_int_fields", -2);
        }
    """
  end
end
