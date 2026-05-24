defmodule Ide.Debugger.Types do
  @moduledoc """
  Shared types for debugger runtime state, timeline rows, and compiler ingest payloads.
  """

  @type simulator_settings :: %{
          optional(String.t()) => term()
        }

  @type watch_profile :: %{
          required(String.t()) => String.t() | integer() | boolean() | nil,
          optional(atom()) => term()
        }

  @type timeline_row :: %{
          required(:seq) => non_neg_integer(),
          required(:raw_seq) => non_neg_integer(),
          required(:type) => String.t(),
          required(:target) => String.t(),
          required(:message) => String.t(),
          optional(:message_source) => String.t() | nil,
          optional(:watch) => map(),
          optional(:companion) => map(),
          optional(:phone) => map()
        }

  @type subscription_row :: %{
          optional(String.t()) => String.t() | integer() | boolean() | nil,
          optional(atom()) => term()
        }

  @type trigger_candidate :: %{
          optional(String.t()) => term(),
          optional(atom()) => term()
        }

  @type compile_ingest_attrs :: %{
          optional(:status) => :ok | :error | String.t(),
          optional(:compiled_path) => String.t(),
          optional(:checked_path) => String.t(),
          optional(:manifest_path) => String.t(),
          optional(:revision) => String.t(),
          optional(:cached) => boolean(),
          optional(:cached?) => boolean(),
          optional(:strict) => boolean(),
          optional(:strict?) => boolean(),
          optional(:error_count) => non_neg_integer(),
          optional(:warning_count) => non_neg_integer(),
          optional(:detail) => String.t(),
          optional(:source_root) => String.t(),
          optional(:schema_version) => term(),
          optional(:diagnostics) => list(),
          optional(:elm_executor_core_ir_b64) => String.t(),
          optional(:elm_executor_metadata) => map(),
          optional(String.t()) => term()
        }

  @type cmd_call :: %{
          optional(String.t()) => String.t() | [term()] | map() | nil,
          optional(atom()) => String.t() | [term()] | map() | nil
        }

  @type companion_bridge_request :: %{
          required(:api) => String.t(),
          required(:op) => String.t(),
          optional(:key) => String.t() | nil,
          optional(:value) => term()
        }

  @type protocol_event :: %{
          optional(:type) => String.t(),
          optional(:payload) => map(),
          optional(String.t()) => String.t() | map() | term(),
          optional(atom()) => String.t() | map() | term()
        }

  @type device_request :: %{
          required(:kind) => String.t(),
          required(:response_message) => String.t(),
          optional(:preview) => term(),
          optional(String.t()) => term()
        }

  @type device_data_request :: device_request()

  @type protocol_schema :: map()

  @type protocol_error :: atom() | String.t() | tuple()

  @type protocol_wire_type ::
          :int | :bool | :string | {:enum, String.t()} | {:union, String.t()}

  @type protocol_ctor_value :: %{
          optional(String.t()) => term(),
          optional(:ctor) => String.t(),
          optional(:args) => list()
        }

  @type protocol_schema_message :: %{
          optional(:name) => String.t(),
          optional(:fields) => [map()],
          optional(atom()) => term()
        }

  @type protocol_message_wire_value :: protocol_ctor_value() | map() | String.t() | nil

  @type protocol_wire_scalar :: String.t() | integer() | float() | boolean()

  @type protocol_wire_arg ::
          protocol_ctor_value() | protocol_wire_scalar() | tuple() | map() | nil

  @type protocol_wire_normalize_input :: protocol_wire_arg()

  @type init_model_values :: %{optional(String.t()) => term()}

  @type elm_introspect :: %{
          optional(String.t()) => term(),
          optional(atom()) => term()
        }

  @type app_model :: %{
          optional(String.t()) => term()
        }

  @type shell :: %{
          optional(String.t()) => term(),
          optional(:elm_introspect) => elm_introspect(),
          optional(:elm_executor_core_ir) => map(),
          optional(:elm_executor_core_ir_b64) => String.t(),
          optional(:elm_executor_metadata) => map(),
          optional(:vector_resource_indices) => map()
        }

  @type execution_model :: app_model() | shell()

  @type runtime_model :: execution_model()

  @type surface_target :: :watch | :companion | :phone

  @type surface_label_input :: surface_target() | String.t() | atom() | nil

  @type wire_scalar :: String.t() | integer() | float() | boolean() | nil

  @type wire_input :: wire_scalar() | list() | map()

  @type elm_maybe :: protocol_ctor_value() | map() | nil

  @type protocol_inbound_row :: %{
          optional(String.t()) => String.t() | map() | list() | nil,
          optional(atom()) => String.t() | map() | list() | nil
        }

  @type subscription_payload :: map() | protocol_ctor_value() | wire_scalar()

  @type view_output_node :: map()

  @type view_output_tree :: map()

  @type runtime_step_result :: %{
          optional(:model_patch) => map(),
          optional(:view_tree) => map() | nil,
          optional(:view_output) => runtime_view_nodes(),
          optional(:protocol_events) => list(),
          optional(:followup_messages) => list(),
          optional(String.t()) => term()
        }

  @type replay_step_message :: %{
          required(:seq) => non_neg_integer(),
          required(:target) => surface_target(),
          required(:message) => String.t()
        }

  @type runtime_fingerprint :: %{optional(String.t()) => term()}

  @type normalized_export_term :: map() | list() | wire_scalar()

  @type static_task_result :: map() | integer() | {map(), map()}

  @type runtime_view_nodes :: [view_output_node()]

  @type auto_fire_candidate :: trigger_candidate()

  @type runtime_entrypoint :: {String.t(), String.t()}

  @type runtime_artifacts :: map()

  @type rendered_tree :: map()

  @type simulator_setting_keys ::
          :platform_target
          | :timeline_limit
          | :auto_fire
          | :watch_profile_id
          | :geolocation
          | :companion_bridge

  @type execution_fallback_reason :: atom() | String.t() | tuple()

  @type execution_error ::
          :invalid_execution_input
          | :invalid_http_command
          | {:invalid_elm_executor_result, term()}
          | {:elmc_runtime_executor_failed, term()}
          | {:invalid_elmc_runtime_result, term()}
          | {:elmc_runtime_unavailable, term()}
          | {:external_runtime_executor_failed, execution_fallback_reason()}
          | {:invalid_external_runtime_result, term()}
          | execution_fallback_reason()

  @type http_executor_error :: :invalid_http_command | protocol_error()

  @type param_list :: [String.t()]
end
