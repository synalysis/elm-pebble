defmodule Elmc.Backend.Pebble.SourceWriter.DispatchCore.TagDispatch.Records.IntTuple do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    static ElmcValue *elmc_pebble_int_tuple_from_values(const int64_t *field_values, int index, int field_count) {
          if (field_count <= 0) return elmc_new_int_take(0);
          if (!field_values || index < 0 || index >= field_count) return NULL;

          ElmcValue *head = elmc_new_int_take(field_values[index]);
          if (!head) return NULL;
          if (index == field_count - 1) return head;

          ElmcValue *tail = elmc_pebble_int_tuple_from_values(field_values, index + 1, field_count);
          if (!tail) {
            elmc_release(head);
            return NULL;
          }

          return elmc_tuple2_take_value(head, tail);
        }

"""
  end
end
