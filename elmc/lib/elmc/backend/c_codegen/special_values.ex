defmodule Elmc.Backend.CCodegen.SpecialValues do
  @moduledoc false

  alias Elmc.Backend.CCodegen.SpecialValues.{Core, Dispatcher, Helpers}
  alias Elmc.Backend.CCodegen.Types

  @spec generated_draw_kind_macro(atom() | integer()) :: String.t()
  defdelegate generated_draw_kind_macro(kind), to: Helpers

  @spec msg_tag_param(Types.ir_expr()) :: Types.ir_expr()
  defdelegate msg_tag_param(expr), to: Core

  @spec subscription_to_msg_params([Types.ir_expr()]) :: [Types.ir_expr()]
  defdelegate subscription_to_msg_params(args), to: Core

  @spec encoded_sub_as_tuple(Types.ir_expr(), [Types.ir_expr()]) :: Types.ir_expr()
  defdelegate encoded_sub_as_tuple(mask_expr, args), to: Core

  @spec encoded_cmd_as_tuple(Types.ir_expr(), [Types.ir_expr()]) :: Types.ir_expr()
  defdelegate encoded_cmd_as_tuple(kind_expr, args), to: Helpers

  @spec normalize_special_target(String.t()) :: String.t()
  defdelegate normalize_special_target(target), to: Core

  @spec constructor_tag(String.t()) :: non_neg_integer()
  defdelegate constructor_tag(name), to: Core

  @spec field_access_expr(Types.ir_expr(), String.t()) :: Types.ir_expr()
  defdelegate field_access_expr(arg_expr, field), to: Helpers

  @spec compiler_folded_union_constructors() :: MapSet.t(String.t())
  defdelegate compiler_folded_union_constructors(), to: Core

  @spec pebble_angle_expr(Types.ir_expr()) :: Types.ir_expr()
  defdelegate pebble_angle_expr(rotation), to: Core

  @spec special_value_from_target(String.t(), Types.special_value_args()) ::
          Types.special_value_result()
  defdelegate special_value_from_target(target, args), to: Dispatcher
end
