defmodule Elmc.Backend.Pebble.HeaderWriter.ApiDecls.InitDispatch do
  @moduledoc false
  alias Elmc.Types, as: Types


  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    int elmc_pebble_init(ElmcPebbleApp *app, ElmcValue *flags);
    int elmc_pebble_init_with_mode(ElmcPebbleApp *app, ElmcValue *flags, int run_mode);
    int elmc_pebble_dispatch_int(ElmcPebbleApp *app, int64_t tag);
    int elmc_pebble_dispatch_tag_value(ElmcPebbleApp *app, int64_t tag, int64_t value);
    int elmc_pebble_dispatch_tag_bool(ElmcPebbleApp *app, int64_t tag, int value);
    int elmc_pebble_dispatch_tag_string(ElmcPebbleApp *app, int64_t tag, const char *value);
    /* Borrows `payload`: caller retains ownership and must elmc_release after return. */
    int elmc_pebble_dispatch_tag_payload(ElmcPebbleApp *app, int64_t tag, ElmcValue *payload);
    int elmc_pebble_dispatch_tag_int_values(
        ElmcPebbleApp *app,
        int64_t outer_tag,
        int64_t inner_tag,
        int field_count,
        const int64_t *field_values);
    /* field_names used only when ELMC_PEBBLE_DEBUG_LOGS; pass NULL in production. */
    int elmc_pebble_dispatch_tag_record_int_fields(
        ElmcPebbleApp *app,
        int64_t tag,
        int field_count,
        const char **field_names,
        const int64_t *field_values);
"""
  end
end

