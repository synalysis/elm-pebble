defmodule Elmc.Backend.Pebble.SourceWriter.DispatchCore.TagDispatch.Records.RecordIntFields.BuildDispatch do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
          int built = 0;
          for (int i = 0; i < field_count; i++) {
            record_values[i] = elmc_new_int_take(field_values[i]);
            if (!record_values[i]) {
              built = i;
              goto cleanup_values;
            }
          }
          built = field_count;

          ElmcValue *payload_value = elmc_record_new_take_value(field_count, field_names, record_values);
          free(record_values);

          if (!payload_value) {
            elmc_release(tag_value);
            ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_record_int_fields", -2);
          }

          ElmcValue *msg = elmc_tuple2_take_value(tag_value, payload_value);
          if (!msg) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_record_int_fields", -2);

          elmc_pebble_prepare_dispatch(app);
          int rc = elmc_worker_dispatch(&app->worker, msg);
          elmc_release(msg);
          ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_record_int_fields", elmc_pebble_finish_dispatch(app, rc));

    """
  end
end
