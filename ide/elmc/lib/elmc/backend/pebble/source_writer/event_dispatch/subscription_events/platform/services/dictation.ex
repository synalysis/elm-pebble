defmodule Elmc.Backend.Pebble.SourceWriter.EventDispatch.SubscriptionEvents.Platform.Services.Dictation do
  @moduledoc false
  alias Elmc.Types, as: Types


  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    int elmc_pebble_dispatch_dictation_status(ElmcPebbleApp *app, int status) {
          if (!app || !app->initialized) return -1;
          if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_DICTATION)) return -8;
          elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_DICTATION);
          if (tag <= 0) return -6;
          if (status < 0) status = 0;
          if (status > 2) status = 2;
          return elmc_pebble_dispatch_tag_value(app, tag, status);
        }

        int elmc_pebble_dispatch_dictation_result(ElmcPebbleApp *app, int is_ok, int error_code, const char *text) {
          if (!app || !app->initialized) return -1;
          if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_DICTATION)) return -8;
          elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_DICTATION);
          if (tag <= 0) return -6;

          RC Rc = RC_SUCCESS;
          ElmcValue *owned[3] = {0};
          ElmcValue *result_payload = NULL;
          CATCH_BEGIN
            if (is_ok) {
              Rc = elmc_new_string(&owned[0], text ? text : "");
              CHECK_RC(Rc);
              Rc = elmc_result_ok_own(&result_payload, owned[0]);
              owned[0] = NULL;
              CHECK_RC(Rc);
            } else if (error_code == 3) {
              Rc = elmc_new_int(&owned[0], 3);
              CHECK_RC(Rc);
              Rc = elmc_new_string(&owned[1], text ? text : "");
              CHECK_RC(Rc);
              Rc = elmc_tuple2_take(&owned[2], owned[0], owned[1]);
              owned[0] = NULL;
              owned[1] = NULL;
              CHECK_RC(Rc);
              Rc = elmc_result_err_own(&result_payload, owned[2]);
              owned[2] = NULL;
              CHECK_RC(Rc);
            } else {
              Rc = elmc_new_int(&owned[0], error_code);
              CHECK_RC(Rc);
              Rc = elmc_result_err_own(&result_payload, owned[0]);
              owned[0] = NULL;
              CHECK_RC(Rc);
            }
          CATCH_END
          elmc_release_array_lifo(owned, 3);
          if (Rc != RC_SUCCESS) {
            elmc_release(result_payload);
            return -2;
          }

          int rc = elmc_pebble_dispatch_tag_payload(app, tag, result_payload);
          elmc_release(result_payload);
          return rc;
        }

"""
  end
end
