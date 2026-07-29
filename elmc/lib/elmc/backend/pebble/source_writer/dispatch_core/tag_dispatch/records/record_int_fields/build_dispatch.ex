defmodule Elmc.Backend.Pebble.SourceWriter.DispatchCore.TagDispatch.Records.RecordIntFields.BuildDispatch do
  @moduledoc false
  alias Elmc.Types, as: Types


  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
          CATCH_BEGIN
            Rc = elmc_new_int(&tag_value, tag);
            CHECK_RC(Rc);
            for (int i = 0; i < field_count; i++) {
              Rc = elmc_new_int(&record_values[i], field_values[i]);
              CHECK_RC(Rc);
              built = i + 1;
            }
            Rc = elmc_record_new_take(&payload_value, field_count, field_names, record_values);
            CHECK_RC(Rc);
            free(record_values);
            record_values = NULL;
            built = 0;
            Rc = elmc_tuple2_take(&msg, tag_value, payload_value);
            CHECK_RC(Rc);
            tag_value = NULL;
            payload_value = NULL;
          CATCH_END
          if (Rc != RC_SUCCESS) {
            goto cleanup_values;
          }

          elmc_pebble_prepare_dispatch(app);
          int rc = elmc_worker_dispatch(&app->worker, msg);
          elmc_release(msg);
          ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_record_int_fields", elmc_pebble_finish_dispatch(app, rc));

    """
  end
end
