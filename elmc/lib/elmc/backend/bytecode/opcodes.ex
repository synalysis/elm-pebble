defmodule Elmc.Backend.Bytecode.Opcodes do
  @moduledoc """
  Stable bytecode opcode table mirroring core plan ops.
  """

  @opcodes %{
    const_int: 1,
    const_immortal_string: 2,
    load_param: 3,
    load_local: 4,
    call_runtime: 5,
    call_fn: 6,
    release: 7,
    publish: 8,
    catch_begin: 9,
    catch_end: 10,
    record_get: 11,
    pebble_cmd: 12,
    ret: 13,
    br: 14,
    br_if: 15,
    switch_tag: 16,
    phi: 17,
    compare: 18,
    test_maybe_nothing: 19,
    switch_ctor_tag: 20,
    record_update: 21,
    list_nil: 22,
    int_arith: 23,
    render_cmd: 24,
    pebble_sub: 25,
    make_closure: 26,
    tuple_proj: 27,
    boxed_binop: 28,
    const_static_list: 29,
    const_c_expr: 30,
    record_get_int: 31
  }

  @spec opcode(atom()) :: non_neg_integer() | nil
  def opcode(op), do: Map.get(@opcodes, op)

  @spec name(non_neg_integer()) :: atom() | nil
  def name(code) do
    Enum.find_value(@opcodes, fn {op, c} -> if c == code, do: op end)
  end

  @spec all() :: [{atom(), non_neg_integer()}]
  def all, do: Enum.sort_by(@opcodes, fn {_, v} -> v end)
end
