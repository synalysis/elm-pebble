defmodule Elmx.Types do
  @moduledoc """
  Shared types for IR lowering, codegen, and debugger runtime.

  ## Wire and Elm values

  * `wire_value`, `wire_map`, `wire_ctor`, `wire_cmd`, `wire_input`, `wire_cmd_input`
  * `elm_value`, `elm_msg`, `maybe_like`, `result_like`, `elm_hof`, `fold_acc`

  ## Collections and JSON

  * `elm_list`, `elm_dict`, `elm_set`, `elm_array`, `json_value`, `json_decoder_spec`

  ## UI and view pipeline

  * `ui_node`, `ui_point`, `ui_bounds`, `ui_color`, `view_shape_input`, `view_output_tree`

  ## Executor and codegen

  * `executor_request`, `runtime_model`, `execution_payload`, `emit_env`, `runtime_handler`

  Qualified stdlib codegen discovery: `Elmx.Runtime.Stdlib.Qualified.handles?/1`.
  Shared list/fold/collection fragments: `Elmx.Runtime.Stdlib.QualifiedCodegen`.
  Module path constants: `Elmx.Runtime.CodegenRefs`.
  """

  @typedoc "Lowered Elm expression node from `ElmEx.IR` (must include `:op`)."
  @type ir_expr :: %{
          required(:op) => atom(),
          optional(atom()) => term()
        }

  @typedoc "IR node lowered to a runtime intrinsic call."
  @type runtime_call_ir :: %{
          required(:op) => :runtime_call,
          required(:function) => String.t(),
          required(:args) => [ir_expr()]
        }

  @typedoc "Qualified-call rewrite argument list (IR subtrees or literals)."
  @type ir_arg_list :: [ir_expr() | term()]

  @typedoc "Comma-separated argument string passed to `Stdlib.Qualified.call/2`."
  @type qualified_arg_code :: String.t()

  @typedoc "Result of `Stdlib.Qualified.call/2` or `Stdlib.qualified_call/2`."
  @type qualified_call_result :: {:ok, String.t()} | :error

  @typedoc "Keyword options for `Stdlib.QualifiedCodegen` container/HOF helpers."
  @type qualified_codegen_opts :: [
          {:module, module()}
          | {:list_param, String.t()}
          | {:acc_param, String.t()}
          | {:container_param, String.t()}
          | {:param, String.t()}
          | {:last_param, String.t()}
        ]

  @typedoc "Result of rewriting a qualified call to a smaller IR subtree."
  @type rewrite_result :: {:ok, ir_expr()} | :error

  @typedoc "Dispatcher module result before kernel fallback."
  @type dispatch_result :: rewrite_result() | :unmatched

  @typedoc "Elm union constructor on the wire (debugger / protocol JSON). Must include `\"ctor\"`."
  @type wire_ctor :: %{optional(String.t()) => String.t() | [wire_value()] | wire_value()}

  @typedoc "String-keyed wire map (view trees, launch context, protocol payloads)."
  @type wire_map :: %{optional(String.t()) => wire_value()}

  @typedoc "Options on a registry handler (`:target`, `:kind`, `:key`, or `:args` reorder indices)."
  @type runtime_handler_opts :: [
          {:target, String.t()}
          | {:kind, String.t()}
          | {:key, String.t()}
          | {:args, [non_neg_integer()]}
        ]

  @typedoc "Registry entry for `elmc_*` / `elmx_*` runtime handler tables."
  @type runtime_handler ::
          {module(), atom()} | {module(), atom(), runtime_handler_opts()}

  @typedoc """
  Single flattened draw op in `runtime_view_output` (string-keyed; `kind` names draw ops).
  Must include `\"kind\"`.
  """
  @type view_output_row :: %{required(String.t()) => wire_value()}

  @typedoc "Options for `Elmx.Runtime.ViewOutput` flattening and resource index resolution."
  @type view_output_opts :: [
          {:vector_resource_indices, %{String.t() => pos_integer()}}
          | {:bitmap_resource_indices, %{String.t() => pos_integer()}}
          | {:animation_resource_indices, %{String.t() => pos_integer()}}
          | {:screen_w, pos_integer()}
          | {:screen_h, pos_integer()}
          | {:runtime_model, runtime_model()}
        ]

  @typedoc "Options for `Cmd.companion_bridge/3`."
  @type companion_bridge_opts :: [
          {:callback, elm_msg()}
          | {:key, String.t()}
          | {:bridge_id, term()}
          | {:payload, term()}
          | {:value, wire_value()}
        ]

  @typedoc "Options for `Cmd.subscription_register/2`."
  @type subscription_register_opts :: [
          {:callback, elm_msg()}
          | {:interval_ms, non_neg_integer()}
        ]

  @typedoc "Options for `Cmd.effect/2` (vibes, light, etc.)."
  @type effect_cmd_opts :: [
          {:variant, String.t() | atom()}
          | {:pattern, term()}
        ]

  @typedoc "Options for `Followups.from_commands/2`."
  @type followups_opts :: [
          {:runtime_model, runtime_model()}
          | {:source_root, String.t()}
        ]

  @typedoc "Opaque Elm runtime cell (list element, dict value, set member, etc.)."
  @type elm_value :: term()

  @typedoc "Elm function passed to higher-order runtime helpers (callback or curried partial)."
  @type elm_hof :: (elm_value() -> elm_value()) | term()

  @typedoc "Elm `Dict` runtime representation (association list with integer keys)."
  @type elm_dict :: [{integer(), elm_value()}]

  @typedoc "Elm `Set` runtime representation (list of members)."
  @type elm_set :: [elm_value()]

  @typedoc "Elm `List` runtime representation."
  @type elm_list :: [elm_value()]

  @typedoc "Elm `String.toList` runtime representation (single-character UTF-8 strings)."
  @type elm_char_list :: [String.t()]

  @typedoc "Elm `Array` runtime representation (list-backed in the Elixir runtime)."
  @type elm_array :: [elm_value()]

  @typedoc "Opaque accumulator passed through Elm `foldl` / `foldr` helpers."
  @type fold_acc :: elm_value()

  @typedoc "Splat argument list for `elmx_*` registry handlers (`Pebble.Dispatch`)."
  @type registry_args :: list()

  @typedoc "IR literal or folded mask value in `Pebble.Subscriptions.batch_mask/1`."
  @type subscription_mask_item :: ir_expr() | non_neg_integer()

  @typedoc "Display shape ctor from Elm `Platform` / launch metadata."
  @type display_shape_like :: wire_ctor() | {atom(), list()} | String.t()

  @typedoc "Values accepted by Elm `Basics.max` / `Basics.min` / `Basics.clamp` in the runtime."
  @type comparable :: number() | String.t()

  @typedoc "Elm 2-tuple in native or wire form."
  @type elm_tuple2 :: {term(), term()} | tuple()

  @typedoc "Tuple-like value for `Core.Tuple` accessors (native, wire, or list)."
  @type elm_tuple_like :: elm_tuple2() | wire_ctor() | tuple() | list()

  @typedoc "Association-list entry before `dict_from_list/1` normalization."
  @type dict_entry_input ::
          {integer() | ui_coord(), elm_value()}
          | [term()]
          | wire_ctor()
          | map()

  @typedoc "Scalar or structured value in debugger wire models."
  @type wire_value ::
          boolean()
          | number()
          | String.t()
          | wire_ctor()
          | nil
          | [wire_value()]
          | wire_map()

  @typedoc "Elm `Maybe` in native or wire form."
  @type maybe_native :: :Nothing | {:Just, elm_value()}
  @type maybe_wire :: wire_ctor()
  @type maybe_like :: maybe_native() | maybe_wire()

  @typedoc "Elm `Result` in native or wire form."
  @type result_native :: {:Ok, elm_value()} | {:Err, elm_value()}
  @type result_wire :: wire_ctor()
  @type result_like :: result_native() | result_wire()

  @typedoc "Normalized Pebble UI preview node from `Elmx.Runtime.Pebble.Ui`."
  @type ui_node :: %{
          optional(:type) => String.t(),
          optional(:label) => String.t(),
          optional(:children) => [ui_node()],
          optional(atom()) => elm_value()
        }

  @typedoc "Numeric coordinate from IR literals, records, or wire maps."
  @type ui_coord :: number() | String.t()

  @typedoc "2D point accepted by `Pebble.Ui` geometry helpers (tuple, record, or wire map)."
  @type ui_point :: {ui_coord(), ui_coord()} | %{optional(String.t()) => ui_coord()} | map()

  @typedoc "Rectangle bounds (x, y, w, h) from IR or wire. Four-element lists are accepted at runtime."
  @type ui_bounds ::
          {ui_coord(), ui_coord(), ui_coord(), ui_coord()}
          | %{optional(String.t()) => ui_coord()}
          | map()

  @typedoc "Color literal for Pebble canvas ops (named atom, packed int, or wire union)."
  @type ui_color :: integer() | atom() | String.t() | wire_ctor()

  @typedoc "Font descriptor from codegen (GFont id, record, or wire union)."
  @type ui_font :: atom() | String.t() | map() | wire_ctor() | term()

  @typedoc "Text/font/options records passed into Pebble UI draw helpers."
  @type ui_text_options :: map() | wire_map() | list()

  @typedoc "Window id or layer index from codegen."
  @type ui_layer_id :: integer() | String.t() | term()

  @typedoc "Draw-op label for `textLabel` (atom ctor or string)."
  @type ui_label :: atom() | String.t()

  @typedoc "Bitmap/vector resource reference from codegen."
  @type ui_resource :: atom() | integer() | String.t() | map() | wire_ctor()

  @typedoc "Path definition from `Pebble.Ui.path/3`, passed to outline/filled helpers."
  @type ui_path :: ui_node()

  @typedoc "Pebble compositing mode (packed int from Elm `CompositingMode`)."
  @type ui_compositing_mode :: ui_coord()

  @typedoc "Values Elm `String` APIs coerce via `to_string/1` or grapheme iteration."
  @type string_like :: String.t() | elm_char_list() | number() | atom()

  @typedoc "Launch reason ctor name, wire union, or debugger string."
  @type launch_reason_like ::
          String.t()
          | atom()
          | wire_ctor()
          | {atom(), list()}
          | nil

  @typedoc "Screen color mode from Elm `Platform` or launch metadata."
  @type color_mode_like ::
          :Color
          | String.t()
          | wire_ctor()
          | {atom(), term()}


  @typedoc "BEAM compile failure detail from `Elmx.Runtime.Loader`."
  @type compile_failure_detail ::
          %{
            optional(:message) => String.t(),
            optional(:file) => String.t() | nil,
            optional(:line) => integer() | nil,
            optional(:description) => String.t() | nil
          }
          | list()
          | term()

  @typedoc "Debugger view tree (string-keyed nodes, aligned with IDE `Types.view_output_tree`)."
  @type view_output_tree :: wire_map()

  @typedoc "Elm view / draw value before `ViewShape.normalize/1` (ctor maps, tags, or preview nodes)."
  @type view_shape_input ::
          ui_node()
          | view_output_tree()
          | wire_ctor()
          | wire_map()
          | {atom(), list()}
          | {integer(), term()}
          | tuple()
          | ui_color()
          | ui_coord()
          | atom()
          | [view_shape_input()]

  @typedoc "Result of `ViewShape.coerce/1` (tree node, nested inputs, or unmapped)."
  @type view_shape_coerce_result :: view_output_tree() | ui_node() | [view_shape_input()] | nil

  @typedoc "Single entry in a flat render-op list passed to `ViewShape.normalize/1`."
  @type render_op_input :: ui_node() | view_output_tree() | wire_ctor() | wire_map()

  @typedoc "Numeric literal from Elm `Basics` math intrinsics."
  @type numeric_input :: number()

  @typedoc "IEEE float markers surfaced by Elm `Basics.isInfinite`."
  @type float_marker :: :infinity | :negative_infinity

  @typedoc "Screen fields on a normalized launch context."
  @type launch_screen :: %{
          optional(String.t()) => integer() | boolean() | String.t() | wire_ctor()
        }

  @typedoc "Normalized launch metadata for `Platform` init."
  @type launch_context :: %{
          optional(String.t()) => wire_value()
        }

  @typedoc "HTTP response expectation attached to an `elm/http` command."
  @type http_expect :: wire_map()

  @typedoc "Request body descriptor for `elm/http` commands (`kind`, `content_type`, `body`, …)."
  @type http_body :: wire_map()

  @typedoc "Wire-format command map from `Elmx.Runtime.Cmd` / `Elmx.Runtime.Http`. Must include `\"kind\"`."
  @type wire_cmd :: wire_map()

  @typedoc "Command map before `Cmd.normalize/1` or inside `batch/1`."
  @type wire_cmd_input :: wire_cmd() | wire_map() | map()

  @typedoc "Runtime value accepted by `Values.wire_value/1`."
  @type wire_input ::
          wire_value()
          | wire_ctor()
          | map()
          | {atom(), list()}
          | atom()
          | tuple()
          | list()

  @typedoc "Pebble data-log tag from Elm `Tag` or a raw integer id."
  @type data_log_tag ::
          integer()
          | {:Tag, integer()}
          | %{optional(String.t()) => String.t() | integer() | [integer()]}
          | %{optional(atom()) => term()}

  @typedoc "Elm `Random.Generator` value passed to `random_int/1`."
  @type random_generator :: %{required(:low) => integer(), required(:high) => integer()}

  @typedoc "JSON-compatible value from `Elmx.Runtime.Json.Encode`."
  @type json_value ::
          nil
          | boolean()
          | number()
          | String.t()
          | [json_value()]
          | %{String.t() => json_value()}

  @typedoc "Opaque composable JSON decoder (`Json.Decode`)."
  @type json_decoder :: {:json_decoder, json_decoder_spec()}

  @typedoc "Primitive or composite spec inside `{:json_decoder, spec}`."
  @type json_primitive :: :string | :int | :float | :bool | :value

  @typedoc "Internal JSON decoder spec carried in `{:json_decoder, spec}`."
  @type json_decoder_spec ::
          json_primitive()
          | {:field, String.t(), json_decoder()}
          | {:list, json_decoder()}
          | {:index, integer(), json_decoder()}
          | {:nullable, json_decoder()}
          | {:maybe, json_decoder()}
          | {:null, json_value()}
          | {:fail, String.t()}
          | {:and_then, (term() -> json_decoder()), json_decoder()}
          | {:lazy, (-> json_decoder())}
          | {:dict, json_decoder()}
          | {:key_value_pairs, json_decoder()}
          | {:map, (term() -> term()), json_decoder()}
          | {:map_n, function(), [json_decoder()]}
          | {:succeed, json_value()}
          | {:one_of, [json_decoder()]}

  @typedoc "Key/value pair accepted by `Json.Encode.object/1`. Two-element lists are accepted at runtime."
  @type json_object_pair :: {String.t(), json_value()}

  @typedoc "Companion storage value before `storage_value_wire/1` normalization."
  @type storage_value_input :: wire_value() | wire_ctor() | {atom(), term()}

  @typedoc """
  Debugger model container passed as `current_model` on executor requests.

  Runtime code accepts atom or string keys (`"runtime_model"`, `"launch_context"`, …).
  """
  @type executor_current_model ::
          wire_map()
          | %{
              optional(:runtime_model) => runtime_model(),
              optional(:launch_context) => launch_context(),
              optional(:runtime_model_source) => String.t()
            }

  @typedoc "Resource label → index maps on `Executor` preview requests."
  @type executor_resource_indices :: %{String.t() => pos_integer()}

  @typedoc """
  Request map for `Elmx.Runtime.Executor` (`current_model`, message, resource indices, …).

  Accepts atom or string keys for IDE wire payloads.
  """
  @type executor_request :: %{
          optional(:message) => String.t() | nil,
          optional(:message_value) => wire_value() | nil,
          optional(:current_model) => executor_current_model() | runtime_model(),
          optional(:source_root) => String.t(),
          optional(:vector_resource_indices) => executor_resource_indices(),
          optional(:bitmap_resource_indices) => executor_resource_indices(),
          optional(:animation_resource_indices) => executor_resource_indices(),
          optional(atom()) => term(),
          optional(String.t()) => term()
        }

  @typedoc "Decoded debugger step message for generated `update/2`."
  @type elm_msg ::
          atom()
          | String.t()
          | boolean()
          | number()
          | tuple()
          | map()
          | list()

  @typedoc "Default payload for synthetic `FrameTick` messages."
  @type frame_tick_payload :: %{
          required(String.t()) => integer()
        }

  @typedoc "Runtime command value after `Values.wire_cmd/1`."
  @type runtime_cmd :: wire_cmd()

  @typedoc "Return type of `Elmx.Runtime.Pebble.runtime_dispatch/2`."
  @type runtime_dispatch_result ::
          wire_cmd()
          | wire_value()
          | ui_node()
          | number()
          | boolean()
          | list()
          | map()
          | result_like()

  @typedoc "Debugger follow-up row derived from init/step commands."
  @type followup_row :: wire_map()

  @typedoc "Synthetic protocol timeline event from `Followups.protocol_events/1`."
  @type protocol_event :: %{
          required(:type) => String.t(),
          required(:payload) => wire_map()
        }

  @typedoc "Elm runtime model as string-keyed maps and wire union values."
  @type runtime_model :: %{optional(String.t()) => wire_value()}

  @typedoc "Monotonic counter threaded through codegen."
  @type emit_counter :: non_neg_integer()

  @typedoc "Result of `Emit.compile_expr/3`."
  @type compile_expr_result :: {iodata(), emit_env(), emit_counter()}

  @typedoc "Codegen environment passed through `Emit.compile_expr/3`."
  @type emit_env :: %{
          optional(:module) => String.t(),
          optional(:emit_mode) => :library | :ide_runtime,
          optional(:constructor_lookup) => map(),
          optional(:record_field_types) => map(),
          optional(:zero_arity_fns) => MapSet.t(String.t()),
          optional(:function_arities) => map(),
          optional(:cross_module_arities) => map(),
          optional(:emit_module_names) => [String.t()],
          optional(:uses_bitwise) => boolean()
        }

  @typedoc "Codegen failure from `Elmx.Backend.ElixirCodegen.emit_project/2`."
  @type emit_error ::
          {:unsupported_op, atom(), String.t()}
          | {:emit_failed, String.t()}

  @typedoc "Options for `Elmx.Backend.ElixirCodegen.emit_project/2`."
  @type emit_options :: %{
          optional(:entry_module) => String.t(),
          optional(:mode) => :library | :ide_runtime,
          optional(:ir_sha256) => String.t(),
          optional(:user_module_names) => [String.t()],
          optional(:ir_full) => ElmEx.IR.t()
        }

  @typedoc "Options for `Elmx.compile/2` and `Elmx.compile_in_memory/2`."
  @type compile_options :: %{
          optional(:entry_module) => String.t(),
          optional(:out_dir) => String.t() | nil,
          optional(:mode) => :library | :ide_runtime,
          optional(:strip_dead_code) => boolean(),
          optional(:revision) => String.t() | nil,
          optional(:source_overrides) => %{optional(String.t()) => String.t()}
        }

  @typedoc "Output of `Elmx.Runtime.Executor.view_generated/2` (view-only evaluation)."
  @type view_preview_payload :: %{
          required(:view_tree) => view_output_tree(),
          required(:view_output) => [view_output_row()]
        }

  @typedoc "Successful output of `Elmx.Runtime.Executor.execute_generated/2`."
  @type execution_payload :: %{
          required(:model_patch) => %{
            required(String.t()) => runtime_model() | String.t()
          },
          required(:view_tree) => view_output_tree(),
          required(:view_output) => [view_output_row()],
          required(:runtime) => %{required(String.t()) => String.t()},
          required(:followup_messages) => [followup_row()],
          required(:protocol_events) => [protocol_event() | wire_map()]
        }

  @typedoc "Executor failure tagged for the IDE debugger adapter."
  @type execution_error :: {:elmx_execution_failed, String.t()}
end
