defmodule Ide.Debugger.StepExecution do
  @moduledoc false

  alias Ide.Debugger.StepExecution.Core
  alias Ide.Debugger.StepExecution.Message
  alias Ide.Debugger.StepExecution.ViewOutput

  defdelegate resolve_message(model, requested_message), to: Message
  defdelegate canonicalize_known_message(message, known_messages), to: Message
  defdelegate message_constructor_known?(message, known_messages), to: Message
  defdelegate unmapped_runtime_result(step, msg_source, known_messages), to: Message
  defdelegate canonicalize_message_constructor(constructor, known_messages), to: Message

  defdelegate runtime_result(step, update_branches), to: Core
  defdelegate normalize_protocol_events(value), to: Core
  defdelegate normalize_followup_messages(value), to: Core
  defdelegate normalize_view_output(value), to: ViewOutput
  defdelegate put_runtime_view_output(model, view_output), to: ViewOutput
  defdelegate tag_runtime_view_output_capture(model), to: ViewOutput
  defdelegate runtime_model_sha256(model), to: ViewOutput
  defdelegate view_output_captured_for_model?(model), to: ViewOutput
  defdelegate preferred_view_output(primary, fallback), to: ViewOutput
  defdelegate resolve_runtime_view_output(execution_model, view_tree, model_for_view, executor_rows), to: ViewOutput
  defdelegate incomplete_stored_view_output?(rows), to: ViewOutput
  defdelegate supplemental_view_output_rows(view_tree, execution_model \\ %{}), to: ViewOutput
  defdelegate choose_runtime_view_output(primary, supplemental), to: ViewOutput
  defdelegate derive_preview_view_output(execution_model, view_tree, preview_model), to: ViewOutput
  defdelegate stale_runtime_view_output?(preview_model, rows), to: ViewOutput
  defdelegate usable_runtime_view_tree?(view_tree, preview_model, ei, execution_model \\ %{}), to: ViewOutput
  defdelegate executor_view_preview(execution_model, app_model, target), to: ViewOutput
  defdelegate stored_view_output_missing_executor_drawables?(stored_rows, fresh_rows, view_tree, execution_model), to: ViewOutput
  defdelegate maybe_executor_view_preview(execution_model, app_model, target, stored_rows), to: ViewOutput
  defdelegate should_refresh_executor_view_preview?(app_model, stored, fresh), to: ViewOutput
  defdelegate placeholder_view_tree?(tree), to: ViewOutput
  defdelegate introspect_parser_view_tree(execution_model, view_tree), to: ViewOutput
  defdelegate introspect_view_tree(introspect), to: ViewOutput
  defdelegate screen_dimensions_for_view_preview(execution_model), to: ViewOutput
  defdelegate runtime_view_output_tree(model, target, runtime_view_tree, opts), to: ViewOutput
  defdelegate render_view_after_update(a, b, c, d, e, f, g), to: Core
  defdelegate normalize_debugger_render_tree(tree), to: ViewOutput
  defdelegate concrete_runtime_view_tree?(tree, ei), to: ViewOutput
  defdelegate parser_expression_view_tree?(tree, ei), to: ViewOutput
  defdelegate introspect_view_usable?(tree, ei), to: ViewOutput
  defdelegate view_tree_has_draw_ops?(tree), to: ViewOutput
  defdelegate unresolved_parser_view_root?(tree, ei), to: ViewOutput
  defdelegate refresh_runtime_fingerprints(model, runtime_model, view_tree), to: ViewOutput
  defdelegate maybe_put_runtime_source(runtime, key, value), to: ViewOutput
  defdelegate view_tree_node_count(tree), to: ViewOutput
  defdelegate stable_term_sha256(term), to: ViewOutput
end
