defmodule Elmc.Backend.Pebble.SourceWriter.DispatchCore.TagDispatch.Records.IntValuesDispatch do
  @moduledoc false
  alias Elmc.Types, as: Types


  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
        int elmc_pebble_dispatch_tag_int_values(
            ElmcPebbleApp *app,
            int64_t outer_tag,
            int64_t inner_tag,
            int field_count,
            const int64_t *field_values) {
          ELMC_PEBBLE_GENERATED_TRACE_ENTER("elmc_pebble_dispatch_tag_int_values");
          if (!app || !app->initialized) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_int_values", -1);
          if (field_count < 0 || (field_count > 0 && !field_values)) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_int_values", -3);

          RC Rc = RC_SUCCESS;
          ElmcValue *inner_tag_value = NULL;
          ElmcValue *inner_payload = NULL;
          ElmcValue *inner_msg = NULL;
          CATCH_BEGIN
            Rc = elmc_new_int(&inner_tag_value, inner_tag);
            CHECK_RC(Rc);
            Rc = elmc_pebble_int_tuple_from_values(&inner_payload, field_values, 0, field_count);
            CHECK_RC(Rc);
            Rc = elmc_tuple2_take(&inner_msg, inner_tag_value, inner_payload);
            inner_tag_value = NULL;
            inner_payload = NULL;
            CHECK_RC(Rc);
          CATCH_END
          if (Rc != RC_SUCCESS) {
            elmc_release(inner_tag_value);
            elmc_release(inner_payload);
            elmc_release(inner_msg);
            ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_int_values", -2);
          }

          int rc = elmc_pebble_dispatch_tag_payload(app, outer_tag, inner_msg);
          elmc_release(inner_msg);
          ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_int_values", rc);
        }

"""
  end
end
