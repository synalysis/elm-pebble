defmodule Elmx.Types do
  @moduledoc """
  Shared types for IR lowering, codegen, and debugger runtime.
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

  @typedoc "Result of rewriting a qualified call to a smaller IR subtree."
  @type rewrite_result :: {:ok, ir_expr()} | :error

  @typedoc "Dispatcher module result before kernel fallback."
  @type dispatch_result :: rewrite_result() | :unmatched

  @typedoc "Elm union / custom type on the wire."
  @type wire_ctor :: %{
          required(:ctor) => String.t(),
          required(:args) => list()
        }

  @typedoc "Scalar or structured value in debugger wire models."
  @type wire_value :: boolean() | number() | String.t() | wire_ctor() | nil

  @typedoc "Normalized launch metadata for `Platform` init."
  @type launch_context :: %{
          optional(String.t()) => wire_value() | wire_ctor() | map()
        }

  @typedoc "Screen fields on a normalized launch context."
  @type launch_screen :: %{
          optional(String.t()) =>
            integer()
            | boolean()
            | String.t()
            | wire_ctor()
        }

  @typedoc "HTTP response expectation attached to an `elm/http` command (`\"kind\"`, `\"to_msg\"`, optional `\"decoder\"`)."
  @type http_expect :: %{
          optional(String.t()) => String.t() | term() | nil
        }

  @typedoc "Request body descriptor for `elm/http` commands (`\"kind\"` plus payload fields)."
  @type http_body :: %{optional(String.t()) => term()}

  @typedoc "Wire-format command map produced by `Elmx.Runtime.Cmd` / `Elmx.Runtime.Http`."
  @type wire_cmd :: %{optional(String.t()) => term()}

  @typedoc "Runtime command value after `Values.wire_cmd/1` (single cmd or batch)."
  @type runtime_cmd :: wire_cmd()

  @typedoc "Debugger follow-up row derived from init/step commands."
  @type followup_row :: %{
          optional(String.t()) => String.t() | term() | wire_cmd() | map()
        }

  @typedoc "Elm runtime model as string-keyed maps and wire union values."
  @type runtime_model :: %{optional(String.t()) => wire_value() | map() | list()}

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
          optional(:uses_bitwise) => boolean(),
          optional(atom()) => term()
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

  @typedoc "Successful output of `Elmx.Runtime.Executor.execute_generated/2`."
  @type execution_payload :: %{
          required(:model_patch) => %{
            required(String.t()) => runtime_model() | String.t()
          },
          required(:view_tree) => map(),
          required(:view_output) => [map()],
          required(:runtime) => %{required(String.t()) => String.t()},
          required(:followup_messages) => [followup_row()],
          required(:protocol_events) => [map()]
        }

  @typedoc "Executor failure tagged for the IDE debugger adapter."
  @type execution_error :: {:elmx_execution_failed, String.t()}
end
