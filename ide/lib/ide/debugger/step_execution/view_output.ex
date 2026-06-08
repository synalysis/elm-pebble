defmodule Ide.Debugger.StepExecution.ViewOutput do
  @moduledoc false

  alias Ide.Debugger.StepExecution.Core

  defdelegate normalize_view_output(value), to: Core
  defdelegate put_runtime_view_output(model, view_output), to: Core
  defdelegate tag_runtime_view_output_capture(model), to: Core
  defdelegate runtime_model_sha256(model), to: Core
  defdelegate view_output_captured_for_model?(model), to: Core
  defdelegate preferred_view_output(primary, fallback), to: Core
  defdelegate resolve_runtime_view_output(execution_model, view_tree, model_for_view, executor_rows), to: Core
  defdelegate incomplete_stored_view_output?(rows), to: Core
  defdelegate supplemental_view_output_rows(view_tree, execution_model \\ %{}), to: Core
  defdelegate choose_runtime_view_output(primary, supplemental), to: Core
  defdelegate derive_preview_view_output(execution_model, view_tree, preview_model), to: Core
  defdelegate stale_runtime_view_output?(preview_model, rows), to: Core
  defdelegate usable_runtime_view_tree?(view_tree, preview_model, ei, execution_model \\ %{}), to: Core
  defdelegate executor_view_preview(execution_model, app_model, target), to: Core
  defdelegate stored_view_output_missing_executor_drawables?(stored_rows, fresh_rows, view_tree, execution_model), to: Core
  defdelegate maybe_executor_view_preview(execution_model, app_model, target, stored_rows), to: Core
  defdelegate should_refresh_executor_view_preview?(app_model, stored, fresh), to: Core
  defdelegate placeholder_view_tree?(tree), to: Core
  defdelegate introspect_parser_view_tree(execution_model, view_tree), to: Core
  defdelegate introspect_view_tree(introspect), to: Core
  defdelegate screen_dimensions_for_view_preview(execution_model), to: Core
  defdelegate runtime_view_output_tree(model, target, runtime_view_tree, opts), to: Core
  defdelegate normalize_debugger_render_tree(tree), to: Core
  defdelegate concrete_runtime_view_tree?(tree, ei), to: Core
  defdelegate parser_expression_view_tree?(tree, ei), to: Core
  defdelegate introspect_view_usable?(tree, ei), to: Core
  defdelegate view_tree_has_draw_ops?(tree), to: Core
  defdelegate unresolved_parser_view_root?(tree, ei), to: Core
  defdelegate refresh_runtime_fingerprints(model, runtime_model, view_tree), to: Core
  defdelegate maybe_put_runtime_source(runtime, key, value), to: Core
  defdelegate view_tree_node_count(tree), to: Core
  defdelegate stable_term_sha256(term), to: Core
end
