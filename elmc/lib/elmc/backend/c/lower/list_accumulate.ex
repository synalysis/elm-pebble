defmodule Elmc.Backend.C.Lower.ListAccumulate do
  @moduledoc false

  # Build a uniquely owned cons spine by consing onto the front, then reverse
  # in place. Avoids `elmc_list_append` (and `elmc_list_reverse`) so fused
  # `List.map` / `List.filter` / `List.indexedMap` do not pull those runtimes.

  @spec cons_front(String.t(), String.t()) :: String.t()
  def cons_front(rev_var, item_var)
      when is_binary(rev_var) and is_binary(item_var) do
    """
        {
          ElmcValue *__acc_next__ = NULL;
          Rc = elmc_list_cons(&__acc_next__, #{item_var}, #{rev_var});
          CHECK_RC(Rc);
          elmc_release(#{item_var});
          #{item_var} = NULL;
          elmc_release(#{rev_var});
          #{rev_var} = __acc_next__;
        }
    """
  end

  @spec cons_front_keep_item(String.t(), String.t()) :: String.t()
  def cons_front_keep_item(rev_var, item_var)
      when is_binary(rev_var) and is_binary(item_var) do
    """
        {
          ElmcValue *__acc_next__ = NULL;
          Rc = elmc_list_cons(&__acc_next__, #{item_var}, #{rev_var});
          CHECK_RC(Rc);
          elmc_release(#{rev_var});
          #{rev_var} = __acc_next__;
        }
    """
  end

  @spec inplace_reverse(String.t()) :: String.t()
  def inplace_reverse(head_var) when is_binary(head_var) do
    """
    {
      ElmcValue *__rev_prev__ = elmc_list_nil();
      ElmcValue *__rev_cur__ = #{head_var};
      while (__rev_cur__ && __rev_cur__->tag == ELMC_TAG_LIST && __rev_cur__->payload != NULL) {
        ElmcCons *__rev_node__ = (ElmcCons *)__rev_cur__->payload;
        ElmcValue *__rev_next__ = __rev_node__->tail;
        __rev_node__->tail = __rev_prev__;
        __rev_prev__ = __rev_cur__;
        __rev_cur__ = __rev_next__;
      }
      #{head_var} = __rev_prev__;
    }
    """
  end
end
