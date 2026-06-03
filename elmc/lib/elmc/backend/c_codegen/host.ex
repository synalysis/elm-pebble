defmodule Elmc.Backend.CCodegen.Host do
  @moduledoc false

  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.FunctionEmit
  alias Elmc.Backend.CCodegen.SpecialValues
  alias Elmc.Backend.CCodegen.Subscriptions
  alias Elmc.Backend.CCodegen.Expr
  alias Elmc.Backend.CCodegen.Hoist
  alias Elmc.Backend.CCodegen.DirectRender.Analysis
  alias Elmc.Backend.CCodegen.DirectRender.CommandDef
  alias Elmc.Backend.CCodegen.DirectRender.Emit.CommandCall, as: EmitCommandCall
  alias Elmc.Backend.CCodegen.DirectRender.Emit.Commands, as: EmitCommands
  alias Elmc.Backend.CCodegen.DirectRender.Emit.Env, as: EmitEnv
  alias Elmc.Backend.CCodegen.DirectRender.Emit.Expr, as: EmitExpr
  alias Elmc.Backend.CCodegen.DirectRender.Emit.MapLoops, as: EmitMapLoops
  alias Elmc.Backend.CCodegen.DirectRender.Emit.Qualified, as: EmitQualified
  alias Elmc.Backend.CCodegen.DirectRender.Emit.StaticDrawTable, as: EmitStaticDrawTable
  alias Elmc.Backend.CCodegen.DirectRender.Emit.Values, as: EmitValues
  alias Elmc.Backend.CCodegen.Native.Bool, as: NativeBool
  alias Elmc.Backend.CCodegen.Native.Float, as: NativeFloat
  alias Elmc.Backend.CCodegen.Native.Int, as: NativeInt
  alias Elmc.Backend.CCodegen.Native.String, as: NativeString
  alias Elmc.Backend.CCodegen.Native.TypedReturn, as: NativeTypedReturn
  alias Elmc.Backend.CCodegen.DirectRender.Filter
  alias Elmc.Backend.CCodegen.Util
  alias Elmc.Backend.CCodegen.DirectRender.Support
  alias Elmc.Backend.CCodegen.DirectRender.TargetRef
  alias Elmc.Backend.CCodegen.CaseCompile
  alias Elmc.Backend.CCodegen.DirectRender.UseSites
  alias Elmc.Backend.CCodegen.Types

  @spec compile_expr(Types.ir_expr() | nil, Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  defdelegate compile_expr(expr, env, counter), to: Elmc.Backend.CCodegen.ExprCompile, as: :compile

  @spec face_ops_append_probe(Types.compile_env(), String.t(), String.t(), Types.compile_counter()) ::
          String.t()
  defdelegate face_ops_append_probe(env, function, result_var, counter),
              to: Elmc.Backend.CCodegen.DebugProbes,
              as: :append_probe

  @spec compile_case_branch_assignment(
          Types.ir_expr(),
          String.t(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: {String.t(), String.t(), Types.compile_counter()}
  defdelegate compile_case_branch_assignment(expr, out, env, counter),
              to: CaseCompile,
              as: :branch_assignment

  @spec binding_key(Types.binding_name()) :: String.t() | term()
  defdelegate binding_key(value), to: EnvBindings

  @spec unwrap_affine_bindings(Types.ir_expr()) :: Types.ir_expr()
  defdelegate unwrap_affine_bindings(expr), to: Elmc.Backend.CCodegen.DirectAffine, as: :unwrap_bindings

  @spec substitute_expr(term(), Types.let_substitutions()) :: term()
  defdelegate substitute_expr(expr, substitutions), to: Expr

  @spec inline_record_field_expr(Types.ir_expr(), String.t(), Types.compile_env()) ::
          Types.ir_expr() | nil
  defdelegate inline_record_field_expr(arg_expr, field, env), to: Expr

  @spec unwrap_let_chain(Types.ir_expr(), Types.let_substitutions()) ::
          {Types.ir_expr(), Types.let_substitutions()}
  defdelegate unwrap_let_chain(expr, bindings), to: Expr

  @spec record_helper_target(Types.ir_expr(), Types.compile_env()) :: Types.function_decl_key() | nil
  defdelegate record_helper_target(expr, env), to: Expr

  @spec record_field_expr(Types.ir_expr() | nil, String.t()) :: Types.ir_expr() | nil
  defdelegate record_field_expr(expr, field), to: Expr

  @spec record_shape(Types.ir_expr(), Types.compile_env()) :: Types.record_shape()
  defdelegate record_shape(expr, env), to: Expr

  @spec record_shape_for_var(Types.compile_env(), String.t()) :: Types.record_shape()
  defdelegate record_shape_for_var(env, name), to: Expr, as: :record_shape_for_var

  @spec record_shape_for_type(String.t(), Types.compile_env()) :: Types.record_shape()
  defdelegate record_shape_for_type(type, env), to: Expr, as: :record_shape_for_type

  @spec battery_alert_field_probe(Types.compile_env(), term(), String.t(), atom()) :: String.t()
  defdelegate battery_alert_field_probe(env, arg, field, position),
              to: Elmc.Backend.CCodegen.DebugProbes,
              as: :field_probe

  @spec agent_probe_region(String.t()) :: String.t()
  defdelegate agent_probe_region(probe), to: Elmc.Backend.CCodegen.DebugProbes, as: :region

  @spec pebble_bound_trig_round_expr?(Types.ir_expr(), Types.compile_env()) :: boolean()
  defdelegate pebble_bound_trig_round_expr?(expr, env),
    to: NativeInt,
    as: :pebble_bound_trig_round_expr?

  @spec record_get_int_expr(String.t(), String.t(), Types.record_shape()) :: String.t()
  defdelegate record_get_int_expr(source, field, fields), to: Expr

  @spec normalize_special_target(String.t()) :: String.t()
  defdelegate normalize_special_target(target), to: SpecialValues

  @spec special_value_from_target(String.t(), [Types.ir_expr()]) :: Types.ir_expr() | nil
  defdelegate special_value_from_target(target, args), to: SpecialValues

  @spec generated_draw_kind_macro(atom() | non_neg_integer()) :: String.t()
  defdelegate generated_draw_kind_macro(kind), to: SpecialValues

  @spec subscription_batch_expr([Types.ir_expr()]) :: Types.ir_expr()
  defdelegate subscription_batch_expr(args), to: Subscriptions

  @spec direct_append_command(
          non_neg_integer(),
          [Types.ir_expr()],
          Types.compile_env(),
          Types.compile_counter()
        ) :: {:ok, String.t(), Types.compile_counter()} | :error
  defdelegate direct_append_command(kind, args, env, counter), to: EmitCommands, as: :append

  @spec direct_emit_settings([Types.ir_expr()], Types.compile_env(), Types.compile_counter()) ::
          Types.direct_emit_result()
  defdelegate direct_emit_settings(settings, env, counter), to: EmitCommands, as: :emit_settings

  @spec direct_setting_supported?(Types.ir_expr()) :: boolean()
  defdelegate direct_setting_supported?(setting), to: Support, as: :setting_supported?

  @spec direct_text_copy_body() :: String.t()
  defdelegate direct_text_copy_body(), to: EmitCommands, as: :text_copy_body

  @spec native_string_expr?(Types.ir_expr(), Types.compile_env()) :: boolean()
  defdelegate native_string_expr?(expr, env), to: NativeString, as: :expr?

  @spec typed_string_expr?(Types.ir_expr(), Types.compile_env()) :: boolean()
  defdelegate typed_string_expr?(expr, env), to: NativeTypedReturn, as: :string_expr?

  @spec compile_native_string_expr(
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.native_string_compile_result()
  defdelegate compile_native_string_expr(expr, env, counter),
    to: NativeString,
    as: :compile_expr

  @spec text_options_expr(Types.ir_expr()) :: Types.ir_expr()
  defdelegate text_options_expr(options), to: Elmc.Backend.CCodegen.DirectRender.Emit.TextOptions, as: :expr

  @spec int_literal_compile_value(Types.ir_expr()) :: integer()
  defdelegate int_literal_compile_value(expr), to: Elmc.Backend.CCodegen.ResourceUnion, as: :int_literal_value

  @spec resource_union_constructor?(String.t(), [Types.ir_expr()]) :: boolean()
  defdelegate resource_union_constructor?(target, args),
              to: Elmc.Backend.CCodegen.ResourceUnion,
              as: :constructor?

  @spec pebble_resource_slot_index(String.t()) :: pos_integer()
  defdelegate pebble_resource_slot_index(target),
              to: Elmc.Backend.CCodegen.ResourceUnion,
              as: :slot_index

  @spec direct_int_value(Types.ir_expr() | nil, Types.compile_env(), Types.compile_counter()) ::
          Types.direct_int_compile_result()
  defdelegate direct_int_value(expr, env, counter), to: EmitValues, as: :int_value

  @spec compile_native_int_expr(
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defdelegate compile_native_int_expr(expr, env, counter),
    to: NativeInt,
    as: :compile_expr

  @spec native_int_compare_safe?(String.t(), Types.ir_expr(), Types.ir_expr(), Types.compile_env()) ::
          boolean()
  defdelegate native_int_compare_safe?(operator, left, right, env),
    to: NativeInt,
    as: :compare_safe?

  @spec compile_native_int_fallback(
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defdelegate compile_native_int_fallback(expr, env, counter),
    to: NativeInt,
    as: :compile_fallback

  @spec compile_native_int_inline_function(
          Types.function_decl_key() | String.t(),
          [Types.ir_expr()],
          Types.compile_env(),
          Types.compile_counter()
        ) :: {:ok, String.t(), String.t(), Types.compile_counter()} | :error
  defdelegate compile_native_int_inline_function(target_key, args, env, counter),
    to: NativeInt,
    as: :inline_function

  @spec compile_native_bool_expr(
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defdelegate compile_native_bool_expr(expr, env, counter),
    to: NativeBool,
    as: :compile_expr

  @spec native_int_expr?(Types.ir_expr(), Types.compile_env()) :: boolean()
  defdelegate native_int_expr?(expr, env), to: NativeInt, as: :expr?

  @spec native_bool_expr?(Types.ir_expr(), Types.compile_env()) :: boolean()
  defdelegate native_bool_expr?(expr, env), to: NativeBool, as: :expr?

  @spec qualified_builtin_operator_name(String.t()) :: String.t() | nil
  defdelegate qualified_builtin_operator_name(target),
              to: Elmc.Backend.CCodegen.BuiltinOperators,
              as: :qualified_operator_name

  @spec qualified_builtin_operator_member?(String.t(), [String.t()]) :: boolean()
  defdelegate qualified_builtin_operator_member?(target, operators),
              to: Elmc.Backend.CCodegen.BuiltinOperators,
              as: :qualified_operator_member?

  @spec typed_function_return?(
          Types.function_decl_key() | nil,
          Types.compile_env(),
          non_neg_integer(),
          String.t()
        ) :: boolean()
  defdelegate typed_function_return?(target, env, arg_count, return_type),
    to: NativeTypedReturn,
    as: :function_return?

  @spec direct_text_options_arg(
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.ir_expr()
  defdelegate direct_text_options_arg(options, env, counter),
              to: Elmc.Backend.CCodegen.DirectRender.Emit.TextOptions,
              as: :arg

  @spec native_function_args?(
          Types.function_declaration(),
          String.t(),
          Types.function_decl_map()
        ) :: boolean()
  defdelegate native_function_args?(decl, module_name, decl_map),
    to: Elmc.Backend.CCodegen.Native.FunctionCall,
    as: :native_args?

  @spec native_int_usage(Types.binding_name(), Types.ir_expr()) :: Types.native_int_usage_stats()
  def native_int_usage(name, expr),
    do: Elmc.Backend.CCodegen.Native.UsageAnalysis.int_usage(name, expr, nil, %{})

  @spec native_int_usage(
          Types.binding_name(),
          Types.ir_expr(),
          String.t() | nil,
          Types.function_decl_map()
        ) :: Types.native_int_usage_stats()
  defdelegate native_int_usage(name, expr, module_name, decl_map),
              to: Elmc.Backend.CCodegen.Native.UsageAnalysis,
              as: :int_usage

  @spec native_bool_usage(
          Types.binding_name(),
          Types.ir_expr(),
          String.t(),
          Types.function_decl_map()
        ) :: Types.native_bool_usage_stats()
  defdelegate native_bool_usage(name, expr, module_name, decl_map),
              to: Elmc.Backend.CCodegen.Native.UsageAnalysis,
              as: :bool_usage

  @spec pebble_angle_expr?(Types.ir_expr()) :: boolean()
  defdelegate pebble_angle_expr?(expr),
              to: Elmc.Backend.CCodegen.Native.BindingAnalysis,
              as: :pebble_angle_expr?

  @spec binding_reference_count(Types.binding_name(), Types.ir_expr()) :: non_neg_integer()
  defdelegate binding_reference_count(name, expr),
              to: Elmc.Backend.CCodegen.Native.BindingAnalysis,
              as: :reference_count

  @spec pebble_angle_optimized_reference_count(Types.binding_name(), Types.ir_expr()) ::
          non_neg_integer()
  defdelegate pebble_angle_optimized_reference_count(name, expr),
              to: Elmc.Backend.CCodegen.Native.BindingAnalysis,
              as: :pebble_angle_optimized_reference_count

  @spec function_arg_types(String.t()) :: [String.t()]
  defdelegate function_arg_types(type), to: Elmc.Backend.CCodegen.TypeParsing

  @spec function_return_type(String.t()) :: String.t()
  defdelegate function_return_type(type), to: Elmc.Backend.CCodegen.TypeParsing

  @spec normalize_type_name(String.t()) :: String.t()
  defdelegate normalize_type_name(type), to: Elmc.Backend.CCodegen.TypeParsing

  @spec split_qualified_function_target(String.t()) :: Types.qualified_function_target()
  defdelegate split_qualified_function_target(target), to: Util

  @spec native_min_max_name(String.t()) :: String.t()
  defdelegate native_min_max_name(function), to: NativeInt

  @spec put_hoisted_native_bool(Types.compile_env(), Types.ir_expr(), String.t()) ::
          Types.compile_env()
  defdelegate put_hoisted_native_bool(env, expr, ref), to: Hoist

  @spec hoisted_native_bool_ref(Types.compile_env(), Types.ir_expr()) :: String.t() | nil
  defdelegate hoisted_native_bool_ref(env, expr), to: Hoist

  @spec hoisted_native_ints_enabled?(Types.compile_env()) :: boolean()
  defdelegate hoisted_native_ints_enabled?(env), to: Hoist

  @spec hoisted_native_int_lookup(Types.compile_env(), Types.ir_expr()) ::
          {:ok, String.t()} | :error
  defdelegate hoisted_native_int_lookup(env, expr), to: Hoist

  @spec merge_process_hoisted_native_ints(Types.compile_env()) :: Types.compile_env()
  defdelegate merge_process_hoisted_native_ints(env), to: Hoist

  @spec register_hoisted_native_int(Types.ir_expr(), String.t()) :: :ok
  defdelegate register_hoisted_native_int(expr, ref), to: Hoist

  @spec maybe_promote_hoisted_native_int(
          Types.ir_expr(),
          Types.compile_env(),
          String.t(),
          String.t(),
          Types.compile_counter()
        ) :: {String.t(), String.t(), Types.compile_counter()}
  defdelegate maybe_promote_hoisted_native_int(expr, env, code, ref, counter), to: Hoist

  @spec direct_command_targets(ElmEx.IR.t(), Types.codegen_opts(), Types.function_decl_map()) ::
          MapSet.t(Types.function_decl_key())
  defdelegate direct_command_targets(ir, opts, decl_map), to: Analysis, as: :targets

  @spec direct_command_target_sets(Types.function_decl_map(), Types.codegen_opts()) ::
          Analysis.target_sets_result()
  defdelegate direct_command_target_sets(decl_map, opts), to: Analysis, as: :target_sets

  @spec direct_supported?(
          Types.ir_expr(),
          String.t(),
          Types.function_decl_map(),
          MapSet.t(Types.function_decl_key())
        ) :: boolean()
  defdelegate direct_supported?(expr, module_name, decl_map, seen),
    to: Support,
    as: :supported?

  @spec c_arg_bindings([String.t()]) :: [Types.c_arg_binding()]
  defdelegate c_arg_bindings(arg_names), to: FunctionEmit

  @spec put_typed_arg_bindings(Types.compile_env(), [Types.c_arg_binding()], String.t() | nil) ::
          Types.compile_env()
  defdelegate put_typed_arg_bindings(env, arg_bindings, type), to: FunctionEmit

  @spec direct_emit_check_env(
          map(),
          String.t(),
          MapSet.t(Types.function_decl_key()),
          Types.function_decl_map()
        ) :: Types.compile_env()
  defdelegate direct_emit_check_env(decl, module_name, direct_targets, decl_map), to: EmitEnv, as: :check_env

  @spec direct_emit_expr(
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.direct_emit_result()
  defdelegate direct_emit_expr(expr, env, counter), to: EmitExpr, as: :emit_expr

  @spec direct_emit_qualified(
          String.t(),
          [Types.ir_expr()],
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.direct_emit_result()
  defdelegate direct_emit_qualified(target, args, env, counter),
    to: EmitQualified,
    as: :emit_qualified

  @spec direct_emit_command_call(
          Types.function_decl_key(),
          [Types.ir_expr()],
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.direct_emit_result()
  defdelegate direct_emit_command_call(target_key, args, env, counter),
    to: EmitCommandCall,
    as: :emit_command_call

  @spec direct_emit_static_render_items(
          [Types.ir_expr()],
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.direct_emit_result()
  defdelegate direct_emit_static_render_items(items, env, counter),
    to: EmitQualified,
    as: :emit_static_render_items

  @spec direct_range_bounds(Types.ir_expr(), Types.compile_env(), Types.compile_counter()) ::
          {:ok, String.t(), String.t(), String.t(), Types.compile_counter()} | :error
  defdelegate direct_range_bounds(list_expr, env, counter), to: EmitValues, as: :range_bounds

  @spec direct_emit_indexed_map_loop(
          Types.ir_expr(),
          Types.ir_expr(),
          Types.direct_emit_target(),
          boolean(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.direct_emit_result()
  defdelegate direct_emit_indexed_map_loop(
                fun_expr,
                list_expr,
                target,
                transparent?,
                env,
                counter
              ),
              to: EmitMapLoops,
              as: :emit_indexed_map_loop

  @spec direct_emit_map_loop(
          Types.ir_expr(),
          Types.ir_expr(),
          Types.direct_emit_target(),
          boolean(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.direct_emit_result()
  defdelegate direct_emit_map_loop(
                fun_expr,
                list_expr,
                target,
                transparent?,
                env,
                counter
              ),
              to: EmitMapLoops,
              as: :emit_map_loop

  @spec direct_emit_lambda_map(
          Types.binding_name(),
          Types.ir_expr(),
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.direct_emit_result()
  defdelegate direct_emit_lambda_map(arg, body, list_expr, env, counter),
    to: EmitMapLoops,
    as: :emit_lambda_map

  @spec draw_affine_template(
          Types.function_decl_map(),
          Types.direct_emit_target(),
          String.t(),
          Types.compile_env()
        ) :: Types.affine_analysis_result()
  defdelegate draw_affine_template(decl_map, target, loop_var, env),
    to: Elmc.Backend.CCodegen.DirectAffine,
    as: :direct_draw_affine_template

  @spec draw_affine_template_indexed(
          Types.function_decl_map(),
          Types.direct_emit_target(),
          Types.compile_env()
        ) :: Types.affine_indexed_template_result()
  defdelegate draw_affine_template_indexed(decl_map, target, env),
    to: Elmc.Backend.CCodegen.DirectAffine,
    as: :direct_draw_affine_template_indexed

  @spec indexed_map_affine_draw_static_list_loop(
          Types.affine_draw_spec(),
          String.t(),
          String.t(),
          String.t(),
          [String.t()],
          map() | nil,
          String.t(),
          [Types.ir_expr()],
          non_neg_integer(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.direct_emit_result()
  defdelegate indexed_map_affine_draw_static_list_loop(
                spec,
                index_param,
                item_param,
                prefix_code,
                prefix_refs,
                native_prefix_fields,
                prefix_release_code,
                static_items,
                next,
                env,
                counter
              ),
              to: Elmc.Backend.CCodegen.DirectAffine,
              as: :indexed_map_affine_draw_static_list_loop

  @spec indexed_map_affine_draw_range_loop(
          Types.affine_draw_spec(),
          String.t(),
          String.t(),
          String.t(),
          [String.t()],
          map() | nil,
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          non_neg_integer(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.direct_emit_result()
  defdelegate indexed_map_affine_draw_range_loop(
                spec,
                index_param,
                item_param,
                prefix_code,
                prefix_refs,
                native_prefix_fields,
                prefix_release_code,
                range_code,
                first_ref,
                last_ref,
                next,
                env,
                counter
              ),
              to: Elmc.Backend.CCodegen.DirectAffine,
              as: :indexed_map_affine_draw_range_loop

  @spec indexed_map_affine_draw_list_loop(
          Types.affine_draw_spec(),
          String.t(),
          String.t(),
          String.t(),
          [String.t()],
          map() | nil,
          String.t(),
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.direct_emit_result()
  defdelegate indexed_map_affine_draw_list_loop(
                spec,
                index_param,
                item_param,
                prefix_code,
                prefix_refs,
                native_prefix_fields,
                prefix_release_code,
                list_expr,
                env,
                counter
              ),
              to: Elmc.Backend.CCodegen.DirectAffine,
              as: :indexed_map_affine_draw_list_loop

  @spec map_affine_draw_range_loop(
          Types.affine_draw_spec(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          non_neg_integer(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.direct_emit_result()
  defdelegate map_affine_draw_range_loop(
                spec,
                prefix_code,
                prefix_release_code,
                range_code,
                first_ref,
                last_ref,
                next,
                env,
                counter
              ),
              to: Elmc.Backend.CCodegen.DirectAffine,
              as: :map_affine_draw_range_loop

  @spec map_affine_draw_list_loop(
          Types.affine_draw_spec(),
          String.t(),
          String.t(),
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.direct_emit_result()
  defdelegate map_affine_draw_list_loop(
                spec,
                prefix_code,
                prefix_release_code,
                list_expr,
                env,
                counter
              ),
              to: Elmc.Backend.CCodegen.DirectAffine,
              as: :map_affine_draw_list_loop

  @spec direct_emit_native_record_fields(
          Types.binding_name(),
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.native_record_emit_result()
  defdelegate direct_emit_native_record_fields(name, value_expr, env, counter),
              to: Elmc.Backend.CCodegen.DirectRender.Emit.NativeRecord,
              as: :emit_fields

  @spec direct_native_text_options_packed_expr(Types.ir_expr()) :: Types.packed_text_options_result()
  defdelegate direct_native_text_options_packed_expr(value_expr),
              to: Elmc.Backend.CCodegen.DirectRender.Emit.TextOptions,
              as: :packed_expr

  @spec direct_native_text_options_let?(
          Types.binding_name(),
          Types.ir_expr(),
          Types.ir_expr(),
          Types.compile_env()
        ) :: boolean()
  defdelegate direct_native_text_options_let?(name, value_expr, in_expr, env),
              to: Elmc.Backend.CCodegen.DirectRender.Emit.TextOptions,
              as: :let?

  @spec direct_native_record_helper_let?(
          Types.binding_name(),
          Types.ir_expr(),
          Types.compile_env()
        ) :: boolean()
  defdelegate direct_native_record_helper_let?(name, value_expr, env),
              to: Elmc.Backend.CCodegen.DirectRender.Emit.NativeRecord,
              as: :helper_let?

  @spec binding_used_in_lambda?(Types.binding_name(), Types.ir_expr()) :: boolean()
  defdelegate binding_used_in_lambda?(name, expr),
              to: Elmc.Backend.CCodegen.Native.BindingAnalysis,
              as: :used_in_lambda?

  @spec pebble_angle_let?(Types.binding_name(), Types.ir_expr(), Types.ir_expr()) :: boolean()
  defdelegate pebble_angle_let?(name, value_expr, in_expr),
              to: Elmc.Backend.CCodegen.Native.UsageAnalysis,
              as: :pebble_angle_let?

  @spec native_function_call_arg_kinds(
          Types.ir_expr(),
          String.t() | nil,
          Types.function_decl_map()
        ) :: {[Types.ir_expr()], [Types.native_function_arg_kind()]} | nil
  defdelegate native_function_call_arg_kinds(expr, module_name, decl_map),
              to: Elmc.Backend.CCodegen.Native.UsageAnalysis,
              as: :function_call_arg_kinds

  @spec native_int_candidate_for_analysis?(Types.binding_name(), Types.ir_expr()) :: boolean()
  defdelegate native_int_candidate_for_analysis?(name, expr),
              to: Elmc.Backend.CCodegen.Native.UsageAnalysis,
              as: :int_candidate_for_analysis?

  @spec compile_native_float_expr(
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  defdelegate compile_native_float_expr(expr, env, counter),
    to: NativeFloat,
    as: :compile_expr

  @spec native_float_expr?(Types.ir_expr(), Types.compile_env()) :: boolean()
  defdelegate native_float_expr?(expr, env), to: NativeFloat, as: :expr?

  @spec direct_static_draw_table_loop(
          [Types.ir_expr()],
          Types.compile_env(),
          Types.compile_counter()
        ) :: {:ok, String.t(), Types.compile_counter()} | :error
  defdelegate direct_static_draw_table_loop(items, env, counter),
    to: EmitStaticDrawTable,
    as: :static_draw_table_loop

  @spec direct_draw_affine_template(
          Types.function_decl_map(),
          Types.function_target(),
          String.t(),
          Types.compile_env()
        ) :: Types.affine_analysis_result()
  defdelegate direct_draw_affine_template(decl_map, target, loop_var, env),
    to: Elmc.Backend.CCodegen.DirectAffine,
    as: :direct_draw_affine_template

  @spec direct_draw_affine_template_indexed(
          Types.function_decl_map(),
          Types.function_target(),
          Types.compile_env()
        ) :: Types.affine_indexed_template_result()
  defdelegate direct_draw_affine_template_indexed(decl_map, target, env),
    to: Elmc.Backend.CCodegen.DirectAffine,
    as: :direct_draw_affine_template_indexed

  @spec direct_static_list_items(Types.ir_expr()) :: {:ok, [Types.ir_expr()]} | :error
  defdelegate direct_static_list_items(expr), to: TargetRef, as: :static_list_items

  @spec unwrap_direct_lets(Types.ir_expr()) :: Types.ir_expr()
  defdelegate unwrap_direct_lets(expr), to: TargetRef, as: :unwrap_lets

  @spec direct_emit_function_target(Types.ir_expr(), String.t()) ::
          Types.function_target() | nil
  defdelegate direct_emit_function_target(expr, module_name),
    to: TargetRef,
    as: :emit_function_target

  @spec direct_map_emit_target(
          Types.ir_expr(),
          String.t(),
          MapSet.t(Types.function_decl_key()),
          Types.function_decl_map()
        ) :: {:ok, Types.direct_emit_target(), boolean()} | :error
  defdelegate direct_map_emit_target(fun_expr, module_name, targets, decl_map),
    to: Support,
    as: :map_emit_target

  @spec filter_direct_targets(
          MapSet.t(Types.function_decl_key()),
          Types.function_decl_map()
        ) :: MapSet.t(Types.function_decl_key())
  defdelegate filter_direct_targets(targets, decl_map), to: Filter, as: :filter

  @spec generic_entry_roots(Types.function_decl_map(), Types.codegen_opts()) :: [
          Types.function_decl_key()
        ]
  defdelegate generic_entry_roots(decl_map, opts), to: Analysis, as: :entry_roots

  @spec affine_pruned_map_callback_targets(
          MapSet.t(Types.function_decl_key()),
          Types.function_decl_map(),
          Types.codegen_opts()
        ) :: MapSet.t(Types.function_decl_key())
  defdelegate affine_pruned_map_callback_targets(targets, decl_map, opts), to: UseSites

  @spec collect_direct_function_use_sites(
          MapSet.t(Types.function_decl_key()),
          Types.function_decl_map()
        ) :: Types.direct_function_use_sites()
  defdelegate collect_direct_function_use_sites(targets, decl_map), to: UseSites, as: :collect

  @spec direct_single_call_prune_targets(
          MapSet.t(Types.function_decl_key()),
          Types.direct_function_use_sites(),
          Types.function_decl_map(),
          Types.codegen_opts()
        ) :: MapSet.t(Types.function_decl_key())
  defdelegate direct_single_call_prune_targets(emit_targets, use_sites, decl_map, opts),
    to: UseSites,
    as: :single_call_prune_targets

  @spec direct_command_def(
          map(),
          map(),
          MapSet.t(Types.function_decl_key()),
          MapSet.t(Types.function_decl_key()),
          Types.function_decl_map()
        ) :: String.t()
  defdelegate direct_command_def(mod, decl, emit_targets, pruned, decl_map), to: CommandDef, as: :def

  @spec native_direct_command_args?(Types.function_declaration()) :: boolean()
  defdelegate native_direct_command_args?(decl), to: CommandDef, as: :native_args?

  @spec native_direct_command_params(Types.function_declaration()) :: String.t()
  defdelegate native_direct_command_params(decl), to: CommandDef, as: :native_params

  @spec direct_command_arg_kinds(Types.function_declaration()) ::
          [Types.direct_command_arg_kind()]
  defdelegate direct_command_arg_kinds(decl), to: CommandDef, as: :arg_kinds
end
