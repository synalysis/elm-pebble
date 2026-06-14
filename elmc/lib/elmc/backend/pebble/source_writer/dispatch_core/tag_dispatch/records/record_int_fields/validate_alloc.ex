defmodule Elmc.Backend.Pebble.SourceWriter.DispatchCore.TagDispatch.Records.RecordIntFields.ValidateAlloc do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
        int elmc_pebble_dispatch_tag_record_int_fields(
            ElmcPebbleApp *app,
            int64_t tag,
            int field_count,
            const char **field_names,
            const int64_t *field_values) {
          ELMC_PEBBLE_GENERATED_TRACE_ENTER("elmc_pebble_dispatch_tag_record_int_fields");
          if (!app || !app->initialized) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_record_int_fields", -1);
          if (field_count <= 0 || !field_names || !field_values) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_record_int_fields", -3);

          ElmcValue *tag_value = elmc_new_int_take(tag);
          if (!tag_value) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_record_int_fields", -2);

          ElmcValue **record_values = (ElmcValue **)malloc(sizeof(ElmcValue *) * field_count);
          if (!record_values) {
            elmc_release(tag_value);
            ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_record_int_fields", -2);
          }

    """
  end
end
