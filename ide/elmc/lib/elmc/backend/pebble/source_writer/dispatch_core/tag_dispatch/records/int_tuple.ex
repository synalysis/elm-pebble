defmodule Elmc.Backend.Pebble.SourceWriter.DispatchCore.TagDispatch.Records.IntTuple do
  @moduledoc false
  alias Elmc.Types, as: Types


  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    static RC elmc_pebble_int_tuple_from_values(ElmcValue **out, const int64_t *field_values, int index, int field_count) {
          RC Rc = RC_SUCCESS;
          ElmcValue *head = NULL;
          ElmcValue *tail = NULL;
          CATCH_BEGIN
            if (field_count <= 0) {
              Rc = elmc_new_int(out, 0);
              CHECK_RC(Rc);
            } else if (!field_values || index < 0 || index >= field_count) {
              Rc = RC_ERR_INVALID_ARG;
              CHECK_RC(Rc);
            } else {
              Rc = elmc_new_int(&head, field_values[index]);
              CHECK_RC(Rc);
              if (index == field_count - 1) {
                *out = head;
                head = NULL;
              } else {
                Rc = elmc_pebble_int_tuple_from_values(&tail, field_values, index + 1, field_count);
                CHECK_RC(Rc);
                Rc = elmc_tuple2_take(out, head, tail);
                head = NULL;
                tail = NULL;
                CHECK_RC(Rc);
              }
            }
          CATCH_END
          elmc_release(head);
          elmc_release(tail);
          return Rc;
        }

"""
  end
end
