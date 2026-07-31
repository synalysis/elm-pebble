defmodule Elmc.Backend.Plan.Lower.SpecialValues do
  @moduledoc """
  Plan-primary entry for qualified-call / runtime rewrite tables.
  """
  alias Elmc.Backend.Plan.Types, as: Types

  alias Elmc.Backend.Plan.Lower.SpecialValues.{Core, Dispatcher, Helpers}

  @type c_int_ir :: %{required(:op) => :c_int_expr, required(:value) => String.t()}

  @type msg_tag_ir :: %{required(:op) => :msg_tag_expr, required(:name) => String.t()}

  @type int_literal_ir :: %{
          required(:op) => :int_literal,
          required(:value) => integer()
        }

  @type msg_tag_param_result :: msg_tag_ir() | int_literal_ir()

  @type field_access_ir :: %{
          required(:op) => :field_access,
          required(:arg) => Types.ir_expr(),
          required(:field) => String.t()
        }

  @type tuple2_ir :: %{
          required(:op) => :tuple2,
          required(:left) => Types.ir_expr(),
          required(:right) => Types.ir_expr()
        }

  @spec generated_draw_kind_macro(atom() | integer()) :: String.t()
  defdelegate generated_draw_kind_macro(kind), to: Helpers

  @spec msg_tag_param(Types.ir_expr()) :: msg_tag_param_result()
  defdelegate msg_tag_param(expr), to: Core

  @spec subscription_to_msg_params([Types.ir_expr()]) :: [msg_tag_param_result()]
  defdelegate subscription_to_msg_params(args), to: Core

  @spec encoded_sub_as_tuple(Types.ir_expr(), [Types.ir_expr()]) :: tuple2_ir()
  defdelegate encoded_sub_as_tuple(mask_expr, args), to: Core

  @spec encoded_cmd_as_tuple(c_int_ir() | Types.ir_expr(), [Types.ir_expr()]) :: tuple2_ir()
  defdelegate encoded_cmd_as_tuple(kind_expr, args), to: Helpers

  @spec normalize_special_target(String.t()) :: String.t()
  defdelegate normalize_special_target(target), to: Core

  @spec constructor_tag(String.t()) :: non_neg_integer()
  defdelegate constructor_tag(name), to: Core

  @spec field_access_expr(Types.ir_expr(), String.t()) :: field_access_ir()
  defdelegate field_access_expr(arg_expr, field), to: Helpers

  @spec compiler_folded_union_constructors() :: MapSet.t(String.t())
  defdelegate compiler_folded_union_constructors(), to: Core

  @spec pebble_angle_expr(Types.ir_expr()) :: Types.ir_expr()
  defdelegate pebble_angle_expr(rotation), to: Core

  @spec special_value_from_target(String.t(), Types.special_value_args()) ::
          Types.special_value_result()
  defdelegate special_value_from_target(target, args), to: Dispatcher

  @spec command_kind_expr(atom()) :: c_int_ir()
  defdelegate command_kind_expr(kind), to: Helpers
end
