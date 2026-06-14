defmodule Elmc.Backend.Pebble.SourceWriter.EventDispatch.SubscriptionEvents.Platform.Services.Dictation do
  @moduledoc false

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

          ElmcValue *result_payload = NULL;
          if (is_ok) {
            ElmcValue *ok_value = elmc_new_string_take(text ? text : "");
            if (elmc_result_ok(&result_payload, ok_value) != RC_SUCCESS) return -2;
            elmc_release(ok_value);
          } else {
            ElmcValue *error_value = NULL;
            if (error_code == 3) {
              error_value =
                  elmc_tuple2_take_value(elmc_new_int_take(3), elmc_new_string_take(text ? text : ""));
            } else {
              error_value = elmc_new_int_take(error_code);
            }
            if (!error_value) return -2;
            if (elmc_result_err(&result_payload, error_value) != RC_SUCCESS) return -2;
            elmc_release(error_value);
          }
          if (!result_payload) return -2;

          int rc = elmc_pebble_dispatch_tag_payload(app, tag, result_payload);
          elmc_release(result_payload);
          return rc;
        }

"""
  end
end
