defmodule Elmc.Backend.CCodegen.Types do
  @moduledoc """
  Shared types for IR-to-C code generation.
  """

  @type ir_literal_op ::
          :int_literal
          | :c_int_expr
          | :msg_tag_expr
          | :string_literal
          | :char_literal
          | :float_literal
          | :cmd_none

  @type ir_cmd_op :: :pebble_cmd
  @type ir_sub_op :: :pebble_sub

  @type ir_var_arith_op :: :add_const | :add_vars | :sub_const

  @type ir_collection_op ::
          :tuple2
          | :list_literal
          | :tuple_second
          | :tuple_second_expr
          | :tuple_first
          | :tuple_first_expr
          | :string_length
          | :string_length_expr
          | :char_from_code
          | :char_from_code_expr

  @type ir_call_op :: :qualified_call | :constructor_call | :call

  @type ir_record_op :: :record_literal | :record_update | :field_access | :field_call

  @type ir_control_op :: :let_in | :if | :compare | :case | :lambda

  @type ir_op ::
          ir_literal_op()
          | ir_cmd_op()
          | ir_var_arith_op()
          | ir_collection_op()
          | ir_call_op()
          | ir_record_op()
          | ir_control_op()
          | :var
          | :runtime_call
          | :unsupported
          | atom()

  @type ir_expr :: %{
          required(:op) => ir_op(),
          optional(atom()) => term()
        }

  @type ir_literal_expr :: %{
          required(:op) => ir_literal_op(),
          optional(atom()) => term()
        }

  @type ir_var_arith_expr :: %{
          required(:op) => ir_var_arith_op(),
          optional(atom()) => term()
        }

  @type ir_collection_expr :: %{
          required(:op) => ir_collection_op(),
          optional(atom()) => term()
        }

  @type ir_call_expr :: %{
          required(:op) => ir_call_op(),
          optional(atom()) => term()
        }

  @type ir_record_expr :: %{
          required(:op) => ir_record_op(),
          optional(atom()) => term()
        }

  @type ir_var_expr :: %{
          required(:op) => :var,
          required(:name) => String.t(),
          optional(atom()) => term()
        }

  @type ir_if_expr :: %{
          required(:op) => :if,
          required(:cond) => ir_expr(),
          required(:then_expr) => ir_expr(),
          required(:else_expr) => ir_expr(),
          optional(atom()) => term()
        }

  @type ir_runtime_call_expr :: %{
          required(:op) => :runtime_call,
          required(:function) => String.t(),
          required(:args) => [ir_expr()],
          optional(atom()) => term()
        }

  @type ir_let_in_expr :: %{
          required(:op) => :let_in,
          required(:name) => binding_name(),
          required(:value_expr) => ir_expr(),
          required(:in_expr) => ir_expr(),
          optional(atom()) => term()
        }

  @type ir_case_expr :: %{
          required(:op) => :case,
          required(:subject) => case_subject(),
          required(:branches) => case_branches(),
          optional(atom()) => term()
        }

  @type ir_lambda_expr :: %{
          required(:op) => :lambda,
          required(:args) => [String.t()] | nil,
          required(:body) => ir_expr(),
          optional(atom()) => term()
        }

  @type ir_qualified_call_expr :: %{
          required(:op) => :qualified_call,
          required(:target) => String.t(),
          required(:args) => [ir_expr()],
          optional(atom()) => term()
        }

  @type ir_list_literal_expr :: %{
          required(:op) => :list_literal,
          required(:items) => [ir_expr()],
          optional(atom()) => term()
        }

  @type ir_record_literal_expr :: %{
          required(:op) => :record_literal,
          required(:fields) => ir_record_fields(),
          optional(atom()) => term()
        }

  @type native_ref :: String.t()
  @type boxed_binding_set :: MapSet.t(String.t())
  @type native_binding_map :: %{String.t() => native_ref()}

  @type let_binding_classification :: :boxed | :native_int | :boxed_int
  @type function_let_analysis_map :: %{binding_name() => let_binding_classification()}

  @type native_record_field_entry :: {String.t(), ir_expr() | nil}
  @type native_record_field_entries :: [native_record_field_entry()]
  @type native_record_emit_result ::
          {:ok, String.t(), compile_env(), compile_counter()} | :error
  @type packed_text_options_result :: {:ok, ir_expr()} | :error
  @type function_target_set :: MapSet.t(function_decl_key())
  @type value_source_result :: {String.t(), String.t(), compile_counter()}

  @type compile_env :: %{
          optional(:__module__) => String.t(),
          optional(:__function_analysis__) => function_let_analysis_map(),
          optional(:__program_decls__) => function_decl_map(),
          optional(:__record_shapes__) => %{String.t() => record_field_names()},
          optional(:__record_field_kinds__) => %{String.t() => %{String.t() => String.t()}},
          optional(:__record_alias_shapes__) => record_alias_shape_map(),
          optional(:__boxed_int_bindings__) => boxed_binding_set(),
          optional(:__boxed_bool_bindings__) => boxed_binding_set(),
          optional(:__boxed_string_bindings__) => boxed_binding_set(),
          optional(:__native_int_bindings__) => native_binding_map(),
          optional(:__native_float_bindings__) => native_binding_map(),
          optional(:__native_bool_bindings__) => native_binding_map(),
          optional(:__native_string_bindings__) => native_binding_map(),
          optional(:__pebble_angle_bindings__) => %{String.t() => ir_expr()},
          optional(:__hoisted_native_bools__) => hoisted_native_map(),
          optional(:__hoisted_native_ints__) => hoisted_native_map(),
          optional(:__hoisted_native_ints_enabled__) => boolean(),
          optional(:__affine_prefix_params__) => %{String.t() => non_neg_integer()},
          optional(:__affine_prefix_shapes__) => [record_shape()],
          optional(atom()) => term()
        }

  @type compile_counter :: non_neg_integer()
  @type compile_result :: {String.t(), String.t(), compile_counter()}
  @type compile_result_or_nil :: compile_result() | nil
  @type compile_ok_result :: {:ok, String.t(), String.t(), compile_counter()} | :error
  @type range_bounds_result ::
          {:ok, String.t(), String.t(), String.t(), compile_counter()} | :error
  @type direct_emit_result :: {:ok, String.t(), compile_counter()} | :error

  @type static_draw_row_kind :: :clear | :text_int | :pixel | :rect | :fill_rect

  @type static_draw_row :: %{
          required(:kind) => static_draw_row_kind(),
          required(:kind_macro) => String.t(),
          required(:params) => [String.t()],
          optional(:setup) => String.t()
        }

  @type static_draw_row_result :: {:ok, static_draw_row()} | :error

  @type static_row_int_result ::
          {:ok, String.t(), String.t(), compile_counter()} | :error

  @type static_record_fields_result ::
          {:ok, String.t(), [String.t()], compile_counter()} | :error
  @type direct_int_compile_result :: {String.t(), String.t(), compile_counter()}
  @type direct_int_builtin_result ::
          {:ok, String.t(), String.t(), compile_counter()} | :error

  @type native_string_compile_result :: {
          String.t(),
          String.t(),
          [String.t()],
          compile_counter()
        }

  @type native_scalar_compile_result :: {String.t(), String.t(), compile_counter()}

  @type pattern_kind ::
          :wildcard
          | :var
          | :int
          | :char
          | :tuple
          | :constructor
          | :record
          | atom()

  @type pattern :: %{
          required(:kind) => pattern_kind(),
          optional(:name) => String.t(),
          optional(:value) => integer(),
          optional(:elements) => [pattern()],
          optional(:arg_pattern) => pattern() | nil,
          optional(:tag) => integer(),
          optional(:bind) => String.t() | nil,
          optional(:fields) => [String.t()],
          optional(atom()) => term()
        }

  @type int_case_pattern :: %{required(:kind) => :int, required(:value) => integer()} | %{required(:kind) => :wildcard}
  @type int_case_branch :: %{required(:pattern) => int_case_pattern(), required(:expr) => ir_expr()}
  @type int_case_branches :: [int_case_branch()]

  @type case_branch :: %{required(:pattern) => pattern(), required(:expr) => ir_expr()}
  @type case_branches :: [case_branch()]
  @type case_subject :: String.t() | ir_expr()

  @type native_int_usage_stats :: %{
          required(:total) => non_neg_integer(),
          required(:boxed) => non_neg_integer(),
          required(:native) => non_neg_integer(),
          required(:native_container) => non_neg_integer()
        }

  @type native_bool_usage_stats :: %{
          required(:total) => non_neg_integer(),
          required(:boxed) => non_neg_integer(),
          required(:tests) => non_neg_integer()
        }

  @type var_name_set :: MapSet.t(binding_name())
  @type lambda_signature :: {:lambda, [String.t()], ir_expr()}

  @type var_usage_context :: :boxed | :native | :native_container | :bool_test | :native_string

  @type native_float_usage_stats :: %{
          required(:total) => non_neg_integer(),
          required(:boxed) => non_neg_integer(),
          required(:native) => non_neg_integer(),
          required(:native_container) => non_neg_integer()
        }

  @type native_string_usage_stats :: %{
          required(:total) => non_neg_integer(),
          required(:boxed) => non_neg_integer(),
          required(:native_string) => non_neg_integer(),
          required(:native_container) => non_neg_integer()
        }

  @type subject_ref :: String.t() | ir_expr()

  @type c_arg_binding :: {String.t(), String.t(), non_neg_integer()}
  @type direct_command_arg_kind :: :native_int | :native_string | :boxed
  @type native_function_arg_kind :: :native_int | :native_bool | :boxed

  @type function_target :: {String.t(), String.t(), [ir_expr()]}
  @type direct_emit_target :: {String.t(), String.t() | nil, [ir_expr()]}
  @type qualified_function_target :: {String.t(), String.t()} | nil
  @type qualified_type_target :: {String.t(), String.t()} | nil

  @type codegen_opts :: Elmc.Types.compile_options()
  @type file_error :: Elmc.Types.file_error()

  @type msg_constructor_pair :: {String.t(), non_neg_integer()}
  @type msg_constructor_list :: [msg_constructor_pair()]

  @type function_decl_key :: {String.t(), String.t()}
  @type function_decl :: ElmEx.IR.Declaration.t()
  @type function_decl_map :: %{function_decl_key() => function_decl()}

  @type ir_record_field :: %{required(:name) => String.t(), required(:expr) => ir_expr()}
  @type ir_record_fields :: [ir_record_field()]
  @type compare_kind :: :eq | :neq | :gt | :gte | :lt | :lte

  @type ir_compare_expr :: %{
          required(:op) => :compare,
          required(:kind) => compare_kind(),
          required(:left) => ir_expr(),
          required(:right) => ir_expr(),
          optional(atom()) => term()
        }
  @type native_record_binding :: {:native_record, %{String.t() => native_ref()}}
  @type env_source_ref :: String.t()
  @type function_declaration :: ElmEx.IR.Declaration.t()

  @type record_field_names :: [String.t()]
  @type record_shape :: record_field_names() | nil
  @type record_alias_shape_map :: %{{String.t(), String.t()} => record_field_names()}
  @type let_substitutions :: %{optional(atom() | String.t()) => ir_expr()}
  @type binding_name :: atom() | String.t() | ir_expr() | term()

  @type affine_label_spec :: {:literal, String.t()} | {:from_int, String.t(), String.t()}

  @type affine_draw_command :: %{
          required(:kind) => atom(),
          required(:kind_macro) => String.t(),
          required(:params) => [term()],
          optional(:label) => affine_label_spec(),
          optional(:setup) => String.t()
        }

  @type affine_draw_body_spec :: %{
          required(:commands) => [affine_draw_command()],
          required(:context_settings) => [ir_expr()],
          optional(:prefix_shapes) => [record_shape()]
        }

  @type affine_draw_spec :: affine_draw_command() | affine_draw_body_spec()
  @type affine_analysis_result :: {:ok, affine_draw_spec()} | :error
  @type affine_indexed_template_result ::
          {:ok, affine_draw_spec(), String.t(), String.t()} | :error
  @type affine_emit_result :: {:ok, String.t(), compile_counter()} | :error

  @type hoist_key :: term()
  @type hoisted_native_map :: %{hoist_key() => native_ref()}

  @type direct_target_sets :: {
          MapSet.t(function_decl_key()),
          MapSet.t(function_decl_key()),
          MapSet.t(function_decl_key())
        }

  @type direct_map_use_kind :: :map | :indexed

  @type direct_map_use_site :: {
          :map,
          direct_map_use_kind(),
          [ir_expr()],
          ir_expr()
        }

  @type direct_function_use_site :: direct_map_use_site | :other

  @type direct_function_use_sites :: %{
          function_decl_key() => [direct_function_use_site()]
        }

  @typedoc "Result of lowering a qualified Pebble/stdlib target via `SpecialValues`."
  @type special_value_result :: ir_expr() | nil

  @typedoc "Argument list passed to `SpecialValues.special_value_from_target/2`."
  @type special_value_args :: [ir_expr()]
end
