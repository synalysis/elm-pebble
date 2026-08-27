defmodule Elmc.Backend.Plan.ScalarKind do
  @moduledoc """
  Single table for native Int / Bool / Float ABI.

  C emit, prototypes, and peel/box calls must look up symbols here instead of
  cloning per-kind helpers. Int-only runtime (list_nth_int, dense LUT, …) stays
  Int-only — this module does not invent float/bool clones of those ops.
  """

  @type kind :: :int | :bool | :float
  @type native_return :: :native_int | :native_bool | :native_float

  @kinds [:int, :bool, :float]
  @native_returns [:native_int, :native_bool, :native_float]

  @spec kinds() :: [kind()]
  def kinds, do: @kinds

  @spec native_returns() :: [native_return()]
  def native_returns, do: @native_returns

  @spec from_elm_type(String.t()) :: kind() | nil
  def from_elm_type("Int"), do: :int
  def from_elm_type("Bool"), do: :bool
  def from_elm_type("Float"), do: :float
  def from_elm_type(_), do: nil

  @spec from_native_return(atom() | nil) :: kind() | nil
  def from_native_return(:native_int), do: :int
  def from_native_return(:native_bool), do: :bool
  def from_native_return(:native_float), do: :float
  def from_native_return(_), do: nil

  @spec native_return(kind()) :: native_return()
  def native_return(:int), do: :native_int
  def native_return(:bool), do: :native_bool
  def native_return(:float), do: :native_float

  @spec native_return?(atom() | nil) :: boolean()
  def native_return?(kind) when kind in @native_returns, do: true
  def native_return?(_), do: false

  @spec native_or_pair?(atom() | nil) :: boolean()
  def native_or_pair?(kind) when kind in @native_returns, do: true
  def native_or_pair?(kind) when kind in [:native_int_pair, :native_list_int_pair], do: true
  def native_or_pair?(_), do: false

  @spec c_type(kind()) :: String.t()
  def c_type(:int), do: "elmc_int_t"
  def c_type(:bool), do: "bool"
  def c_type(:float), do: "double"

  @spec c_out_type(kind() | native_return()) :: String.t()
  def c_out_type(kind) when kind in @kinds, do: "#{c_type(kind)} *out"

  def c_out_type(native) when native in @native_returns,
    do: c_out_type(from_native_return(native))

  @spec peel(kind()) :: String.t()
  def peel(:int), do: "elmc_as_int"
  def peel(:bool), do: "elmc_as_bool"
  def peel(:float), do: "elmc_as_float"

  @spec box(kind()) :: String.t()
  def box(:int), do: "elmc_new_int"
  def box(:bool), do: "elmc_new_bool"
  def box(:float), do: "elmc_new_float"

  @spec zero(kind()) :: String.t()
  def zero(:int), do: "0"
  def zero(:bool), do: "false"
  def zero(:float), do: "0.0"

  @spec local_name(kind(), non_neg_integer()) :: String.t()
  def local_name(:int, reg) when is_integer(reg), do: "plan_native_int_#{reg}"
  def local_name(:bool, reg) when is_integer(reg), do: "plan_native_bool_#{reg}"
  def local_name(:float, reg) when is_integer(reg), do: "plan_native_float_#{reg}"

  @spec local_name_from_native(native_return(), non_neg_integer()) :: String.t()
  def local_name_from_native(native, reg) when native in @native_returns and is_integer(reg),
    do: local_name(from_native_return(native), reg)
end
