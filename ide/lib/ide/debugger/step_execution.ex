defmodule Ide.Debugger.StepExecution do
  @moduledoc false

  alias Ide.Debugger.IntrospectAccess
  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.RuntimeExecutor
  alias Ide.Debugger.RuntimeViewOutput
  alias Ide.Debugger.StepInput
  alias Ide.Debugger.Types
  alias Ide.Debugger.Types.StepExecutionContract

  @type resolve_result :: {
          String.t(),
          String.t(),
          [String.t()],
          [String.t()],
          non_neg_integer()
        }

  @spec resolve_message(Types.execution_model(), String.t() | nil) ::
          {String.t(), String.t(), [String.t()], [String.t()], non_neg_integer()}
  def resolve_message(model, requested_message) when is_map(model) do
    ei = RuntimeArtifacts.require_introspect(model)
    msg_constructors = IntrospectAccess.list(ei, "msg_constructors")
    update_branches = IntrospectAccess.list(ei, "update_case_branches")

    known_messages =
      if msg_constructors != [] do
        msg_constructors
      else
        update_branches
      end

    cursor = integer_or_zero(Map.get(model, "runtime_message_cursor"))

    cond do
      is_binary(requested_message) and String.trim(requested_message) != "" ->
        message = canonicalize_known_message(String.trim(requested_message), known_messages)
        {message, "provided", known_messages, update_branches, cursor + 1}

      known_messages != [] ->
        idx = rem(cursor, length(known_messages))
        message = Enum.at(known_messages, idx) || "Tick"
        {message, "auto_cycle", known_messages, update_branches, cursor + 1}

      true ->
        {"Tick", "default", [], update_branches, cursor + 1}
    end
  end

  @spec canonicalize_known_message(String.t(), [String.t()]) :: String.t()
  def canonicalize_known_message(message, known_messages) when is_binary(message) do
    trimmed = String.trim(message)

    case String.split(trimmed, ~r/\s+/, parts: 2) do
      [constructor, payload] when is_binary(payload) and payload != "" ->
        canonical_constructor = canonicalize_message_constructor(constructor, known_messages)
        "#{canonical_constructor} #{payload}"

      _ ->
        needle = String.downcase(trimmed)

        Enum.find(known_messages, trimmed, fn known ->
          if is_binary(known) do
            known_down = String.downcase(known)

            known_down == needle or
              String.starts_with?(needle, known_down <> " ") or
              String.starts_with?(needle, known_down <> "(")
          else
            false
          end
        end)
    end
  end

  @spec canonicalize_message_constructor(String.t(), [String.t()]) :: String.t()
  def canonicalize_message_constructor(constructor, known_messages) when is_binary(constructor) do
    ctor_down = String.downcase(constructor)

    Enum.find_value(known_messages, constructor, fn known ->
      if is_binary(known) do
        known_ctor =
          known
          |> String.trim()
          |> String.split(~r/\s+/, parts: 2)
          |> List.first()

        if is_binary(known_ctor) and String.downcase(known_ctor) == ctor_down do
          known_ctor
        end
      end
    end)
  end

  @spec runtime_result(StepInput.t(), [String.t()]) ::
          {:ok, Types.runtime_step_result()} | {:error, Types.execution_error()}
  def runtime_result(%StepInput{} = step, update_branches)
      when is_binary(step.message) do
    request =
      step
      |> StepExecutionContract.request_from(update_branches: update_branches)
      |> Ide.Debugger.RuntimeExecutor.Request.to_map()

    case executor_module().execute(request) do
      {:ok, %{model_patch: patch} = result} when is_map(patch) ->
        if is_map(Map.get(patch, "runtime_model")) do
          {:ok,
           result
           |> Map.put(
             :view_output,
             normalize_view_output(
               Map.get(result, :view_output) || Map.get(patch, "runtime_view_output")
             )
           )
           |> Map.put(
             :protocol_events,
             normalize_protocol_events(Map.get(result, :protocol_events))
           )
           |> Map.put(
             :followup_messages,
             normalize_followup_messages(Map.get(result, :followup_messages))
           )
           |> StepExecutionContract.step_result_from_executor()}
        else
          {:error, {:core_ir_execution_failed, :missing_runtime_model}}
        end

      {:error, _} = err ->
        err

      _ ->
        {:error, {:core_ir_execution_failed, :invalid_executor_result}}
    end
  end

  @spec normalize_protocol_events(list()) :: [Types.protocol_timeline_event()]
  def normalize_protocol_events(value) when is_list(value), do: value
  def normalize_protocol_events(_), do: []

  @spec normalize_followup_messages(list()) :: [String.t()]
  def normalize_followup_messages(value) when is_list(value), do: value
  def normalize_followup_messages(_), do: []

  @spec normalize_view_output(list()) :: Types.runtime_view_nodes()
  def normalize_view_output(value) when is_list(value), do: value
  def normalize_view_output(_), do: []

  @spec put_runtime_view_output(Types.app_model(), Types.runtime_view_nodes()) ::
          Types.app_model()
  def put_runtime_view_output(model, view_output) when is_map(model) do
    case normalize_view_output(view_output) do
      [] ->
        model

      rows ->
        model
        |> Map.put("runtime_view_output", rows)
        |> tag_runtime_view_output_capture()
    end
  end

  @doc false
  @spec tag_runtime_view_output_capture(Types.app_model()) :: Types.app_model()
  def tag_runtime_view_output_capture(model) when is_map(model) do
    sha = runtime_model_sha256(model)

    model
    |> Map.put("runtime_view_output_model_sha256", sha)
    |> then(fn tagged ->
      case Map.get(tagged, "runtime_model") || Map.get(tagged, :runtime_model) do
        %{} = runtime_model ->
          Map.put(
            tagged,
            "runtime_model",
            Map.put(runtime_model, "runtime_view_output_model_sha256", sha)
          )

        _ ->
          tagged
      end
    end)
  end

  @runtime_view_capture_keys ~w(
    runtime_view_output runtime_view_output_model_sha256 runtime_view_tree
    runtime_view_tree_source runtime_last_message runtime_message_source
  )

  @doc false
  @spec runtime_model_sha256(Types.app_model() | Types.inner_runtime_model()) :: String.t()
  def runtime_model_sha256(model) when is_map(model) do
    model
    |> RuntimeArtifacts.preview_runtime_model()
    |> Map.drop(@runtime_view_capture_keys)
    |> stable_term_sha256()
  end

  @doc false
  @spec view_output_captured_for_model?(Types.app_model() | Types.inner_runtime_model()) ::
          boolean()
  def view_output_captured_for_model?(model) when is_map(model) do
    stored_sha =
      Map.get(model, "runtime_view_output_model_sha256") ||
        get_in(model, ["runtime_model", "runtime_view_output_model_sha256"]) ||
        get_in(model, [:runtime_model, :runtime_view_output_model_sha256])

    case stored_sha do
      sha when is_binary(sha) -> sha == runtime_model_sha256(model)
      _ -> true
    end
  end

  @spec preferred_view_output(Types.runtime_view_nodes(), Types.runtime_view_nodes()) ::
          Types.runtime_view_nodes()
  def preferred_view_output(primary, fallback) do
    choose_runtime_view_output(primary, fallback)
  end

  @spec resolve_runtime_view_output(
          Types.execution_model(),
          Types.view_output_tree(),
          Types.app_model(),
          Types.runtime_view_nodes()
        ) :: Types.runtime_view_nodes()
  def resolve_runtime_view_output(execution_model, view_tree, model_for_view, executor_rows)
      when is_map(execution_model) and is_map(view_tree) and is_map(model_for_view) do
    resource_opts = view_output_resource_opts(execution_model)

    supplemental = supplemental_view_output_rows(view_tree, execution_model)

    rows =
      case normalize_view_output(executor_rows) do
        [] ->
          supplemental

        rows ->
          rows = Elmx.Runtime.ViewOutput.apply_resource_indices(rows, resource_opts)

          if view_output_captured_for_model?(model_for_view) do
            maybe_merge_supplemental_view_output(rows, supplemental)
          else
            rows
          end
      end

    rows =
      if view_tree_has_draw_ops?(view_tree) do
        rows
        |> then(fn rows ->
          if unresolved_vector_view_output_rows?(rows),
            do: merge_vector_view_output_rows(rows, supplemental),
            else: rows
        end)
        |> then(fn rows ->
          if unresolved_bitmap_view_output_rows?(rows),
            do: merge_bitmap_view_output_rows(rows, supplemental),
            else: rows
        end)
      else
        rows
      end

    rows
  end

  defp view_output_resource_opts(execution_model) when is_map(execution_model) do
    [
      vector_resource_indices: RuntimeArtifacts.vector_resource_indices(execution_model),
      bitmap_resource_indices: RuntimeArtifacts.bitmap_resource_indices(execution_model),
      animation_resource_indices: RuntimeArtifacts.animation_resource_indices(execution_model)
    ]
  end

  @supplemental_drawable_kinds ~w(
    bitmap_in_rect arc rotated_bitmap bitmap_sequence_at
    path_filled path_outline path_outline_open
  )

  defp maybe_merge_supplemental_view_output(rows, supplemental)
       when is_list(rows) and is_list(supplemental) do
    if missing_supplemental_drawables?(rows, supplemental) do
      merge_supplemental_drawable_rows(rows, supplemental)
    else
      rows
    end
  end

  defp maybe_merge_supplemental_view_output(rows, _supplemental), do: rows

  defp missing_supplemental_drawables?(primary, supplemental) do
    Enum.any?(@supplemental_drawable_kinds, fn kind ->
      Enum.any?(supplemental, &(view_output_row_kind(&1) == kind)) and
        not primary_has_drawable_kind?(primary, kind)
    end)
  end

  defp primary_has_drawable_kind?(rows, "bitmap_in_rect") do
    Enum.any?(rows, fn row ->
      view_output_row_kind(row) == "bitmap_in_rect" and
        view_output_row_int(row, "bitmap_id", 0) > 0
    end)
  end

  defp primary_has_drawable_kind?(rows, kind) do
    Enum.any?(rows, &(view_output_row_kind(&1) == kind))
  end

  defp merge_supplemental_drawable_rows(primary, supplemental) do
    kinds_to_add =
      Enum.filter(@supplemental_drawable_kinds, fn kind ->
        Enum.any?(supplemental, &(view_output_row_kind(&1) == kind)) and
          not primary_has_drawable_kind?(primary, kind)
      end)

    added = Enum.filter(supplemental, &(view_output_row_kind(&1) in kinds_to_add))
    primary ++ added
  end

  defp view_output_row_kind(row) when is_map(row) do
    to_string(Map.get(row, "kind") || Map.get(row, :kind) || "")
  end

  defp view_output_row_int(row, key, default) when is_map(row) do
    case Map.get(row, key) || Map.get(row, String.to_atom(key)) do
      n when is_integer(n) -> n
      n when is_float(n) -> trunc(n)
      _ -> default
    end
  end

  @doc false
  @incomplete_view_output_companions ~w(
    fill_circle circle line path arc fill_radial bitmap_in_rect rotated_bitmap
    bitmap_sequence_at vector_at vector_sequence_at
  )

  @spec incomplete_stored_view_output?(Types.runtime_view_nodes()) :: boolean()
  def incomplete_stored_view_output?(rows) when is_list(rows) do
    has_text = Enum.any?(rows, &(view_output_row_kind(&1) in ["text", "text_label", "text_int"]))
    has_fill = Enum.any?(rows, &(view_output_row_kind(&1) == "fill_rect"))
    has_bitmap = primary_has_drawable_kind?(rows, "bitmap_in_rect")

    has_other_drawables =
      Enum.any?(rows, &(view_output_row_kind(&1) in @incomplete_view_output_companions))

    has_text and has_fill and not has_bitmap and not has_other_drawables
  end

  def incomplete_stored_view_output?(_rows), do: false

  defp unresolved_vector_view_output_rows?(rows) when is_list(rows) do
    Enum.any?(rows, fn
      %{"kind" => kind, "vector_id" => 0}
      when kind in ["vector_at", "vector_sequence_at"] ->
        true

      %{kind: kind, vector_id: 0}
      when kind in [:vector_at, :vector_sequence_at] ->
        true

      _ ->
        false
    end)
  end

  defp merge_vector_view_output_rows(rows, fresh_rows)
       when is_list(rows) and is_list(fresh_rows) do
    keep = Enum.reject(rows, &vector_view_output_row?/1)
    vectors = Enum.filter(fresh_rows, &vector_view_output_row?/1)
    keep ++ vectors
  end

  defp unresolved_bitmap_view_output_rows?(rows) when is_list(rows) do
    Enum.any?(rows, fn
      %{"kind" => kind, "bitmap_id" => 0}
      when kind in ["bitmap_in_rect", "rotated_bitmap"] ->
        true

      %{kind: kind, bitmap_id: 0} when kind in [:bitmap_in_rect, :rotated_bitmap] ->
        true

      %{"kind" => "bitmap_sequence_at", "animation_id" => 0} ->
        true

      %{kind: :bitmap_sequence_at, animation_id: 0} ->
        true

      _ ->
        false
    end)
  end

  defp merge_bitmap_view_output_rows(rows, fresh_rows)
       when is_list(rows) and is_list(fresh_rows) do
    keep = Enum.reject(rows, &bitmap_view_output_row?/1)
    bitmaps = Enum.filter(fresh_rows, &bitmap_view_output_row?/1)
    keep ++ bitmaps
  end

  defp bitmap_view_output_row?(%{"kind" => kind})
       when kind in ["bitmap_in_rect", "rotated_bitmap", "bitmap_sequence_at"],
       do: true

  defp bitmap_view_output_row?(%{kind: kind})
       when kind in [:bitmap_in_rect, :rotated_bitmap, :bitmap_sequence_at],
       do: true

  defp bitmap_view_output_row?(_), do: false

  defp vector_view_output_row?(%{"kind" => kind})
       when kind in ["vector_at", "vector_sequence_at"],
       do: true

  defp vector_view_output_row?(%{kind: kind}) when kind in [:vector_at, :vector_sequence_at],
    do: true

  defp vector_view_output_row?(_), do: false

  @doc false
  @spec supplemental_view_output_rows(Types.view_output_tree(), Types.execution_model()) ::
          Types.runtime_view_nodes()
  def supplemental_view_output_rows(view_tree, execution_model \\ %{})

  def supplemental_view_output_rows(%{"type" => _} = view_tree, execution_model) do
    if view_tree_has_draw_ops?(view_tree) and Code.ensure_loaded?(Elmx.Runtime.ViewOutput) do
      preview_model =
        execution_model
        |> RuntimeArtifacts.preview_runtime_model()
        |> Map.merge(screen_dimensions_for_view_preview(execution_model))

      Elmx.Runtime.ViewOutput.from_view_tree(view_tree,
        vector_resource_indices: RuntimeArtifacts.vector_resource_indices(execution_model),
        bitmap_resource_indices: RuntimeArtifacts.bitmap_resource_indices(execution_model),
        animation_resource_indices: RuntimeArtifacts.animation_resource_indices(execution_model),
        screen_w: Map.get(preview_model, "screenW") || Map.get(preview_model, :screenW),
        screen_h: Map.get(preview_model, "screenH") || Map.get(preview_model, :screenH),
        runtime_model: preview_model
      )
    else
      []
    end
  end

  def supplemental_view_output_rows(_view_tree, _execution_model), do: []

  @spec choose_runtime_view_output(Types.runtime_view_nodes(), Types.runtime_view_nodes()) ::
          Types.runtime_view_nodes()
  def choose_runtime_view_output(primary, _supplemental) do
    normalize_view_output(primary)
  end

  @positioned_view_output_kinds ~w(
    circle fill_circle line text text_label round_rect fill_rect rect pixel
    vector_at vector_sequence_at bitmap_sequence_at arc fill_radial
  )

  @spec derive_preview_view_output(
          Types.execution_model(),
          Types.view_output_tree(),
          Types.inner_runtime_model()
        ) :: Types.preview_view_derivation()
  def derive_preview_view_output(execution_model, view_tree, preview_model)
      when is_map(execution_model) and is_map(view_tree) and is_map(preview_model) do
    preview_model =
      preview_model
      |> RuntimeArtifacts.preview_runtime_model()
      |> Map.merge(screen_dimensions_for_view_preview(execution_model))

    stored_rows =
      Map.get(preview_model, "runtime_view_output") ||
        Map.get(preview_model, :runtime_view_output) ||
        []

    cond do
      stale_runtime_view_output?(preview_model, stored_rows) ->
        case executor_view_preview(execution_model, %{"runtime_model" => preview_model}, :watch) do
          {:ok, preview} ->
            preview

          :error ->
            derive_preview_view_output_from_trees(execution_model, view_tree, preview_model)
        end

      stored_rows == [] and RuntimeArtifacts.versioned_elmx_artifacts?(execution_model) ->
        case executor_view_preview(execution_model, %{"runtime_model" => preview_model}, :watch) do
          {:ok, preview} ->
            preview

          :error ->
            derive_preview_view_output_from_trees(execution_model, view_tree, preview_model)
        end

      true ->
        derive_preview_view_output_from_trees(execution_model, view_tree, preview_model)
    end
  end

  @spec derive_preview_view_output_from_trees(
          Types.execution_model(),
          Types.view_output_tree(),
          Types.inner_runtime_model()
        ) :: Types.preview_view_derivation()
  defp derive_preview_view_output_from_trees(execution_model, view_tree, preview_model) do
    ei = RuntimeArtifacts.require_introspect(execution_model)

    view_tree =
      cond do
        concrete_runtime_view_tree?(view_tree, ei) ->
          view_tree

        true ->
          RuntimeViewOutput.tree(preview_model, :watch) ||
            introspect_parser_view_tree(execution_model, view_tree)
      end

    stored_rows =
      Map.get(preview_model, "runtime_view_output") ||
        Map.get(preview_model, :runtime_view_output) ||
        []

    view_output =
      if stored_rows != [] and not stale_runtime_view_output?(preview_model, stored_rows) do
        []
      else
        supplemental_view_output_rows(view_tree, execution_model)
      end

    %{view_output: view_output, view_tree: view_tree}
  end

  @doc false
  @spec stale_runtime_view_output?(Types.inner_runtime_model(), Types.runtime_view_nodes()) ::
          boolean()
  def stale_runtime_view_output?(preview_model, rows)
      when is_map(preview_model) and is_list(rows) do
    {screen_w, screen_h} = preview_screen_dimensions(preview_model)

    screen_w > 0 and screen_h > 0 and
      (not view_output_captured_for_model?(preview_model) or
         zero_geometry_positioned_rows?(rows) or empty_runtime_text_rows?(rows) or
         incomplete_stored_view_output?(rows))
  end

  def stale_runtime_view_output?(_preview_model, _rows), do: false

  defp empty_runtime_text_rows?(rows) when is_list(rows) do
    Enum.any?(rows, fn
      %{"kind" => kind, "text" => text}
      when kind in ["text", "text_label", "text_int"] and text in ["", nil] ->
        true

      %{kind: kind, text: text}
      when kind in [:text, :text_label, :text_int] and text in ["", nil] ->
        true

      _ ->
        false
    end)
  end

  @doc false
  @spec usable_runtime_view_tree?(
          Types.view_output_tree(),
          Types.inner_runtime_model(),
          Types.elm_introspect(),
          Types.execution_model()
        ) :: boolean()
  def usable_runtime_view_tree?(view_tree, preview_model, ei, execution_model \\ %{})

  def usable_runtime_view_tree?(view_tree, preview_model, ei, execution_model)
      when is_map(view_tree) and is_map(preview_model) and is_map(ei) and is_map(execution_model) do
    concrete_runtime_view_tree?(view_tree, ei) and view_tree_has_draw_ops?(view_tree) and
      not stale_runtime_view_output?(
        preview_model,
        supplemental_view_output_rows(view_tree, execution_model)
      )
  end

  def usable_runtime_view_tree?(_view_tree, _preview_model, _ei, _execution_model), do: false

  @spec executor_view_preview(
          Types.execution_model(),
          Types.app_model(),
          Types.surface_target()
        ) :: {:ok, Types.preview_view_derivation()} | :error
  def executor_view_preview(execution_model, app_model, target)
      when is_map(execution_model) and is_map(app_model) and
             target in [:watch, :companion, :phone] do
    if RuntimeArtifacts.versioned_elmx_artifacts?(execution_model) do
      runtime_model = RuntimeArtifacts.preview_runtime_model(app_model)

      request =
        %{
          elmx_manifest: Map.get(execution_model, "elmx_manifest"),
          elmx_revision: Map.get(execution_model, "elmx_revision"),
          current_model: %{
            "launch_context" =>
              Map.get(app_model, "launch_context") ||
                Map.get(execution_model, "launch_context") || %{},
            "runtime_model" => runtime_model
          },
          introspect: RuntimeArtifacts.require_introspect(execution_model)
        }
        |> Map.merge(RuntimeArtifacts.execution_artifacts(execution_model))

      case RuntimeExecutor.view(request) do
        {:ok, %{view_tree: view_tree, view_output: view_output}}
        when is_map(view_tree) ->
          {:ok, %{view_output: normalize_view_output(view_output), view_tree: view_tree}}

        _ ->
          :error
      end
    else
      :error
    end
  end

  def executor_view_preview(_execution_model, _preview_model, _target), do: :error

  @doc false
  @spec stored_view_output_missing_executor_drawables?(
          Types.execution_model(),
          Types.app_model(),
          Types.surface_target(),
          Types.runtime_view_nodes()
        ) :: boolean()
  def stored_view_output_missing_executor_drawables?(
        execution_model,
        app_model,
        target,
        stored_rows
      )
      when is_map(execution_model) and is_map(app_model) and is_list(stored_rows) do
    case maybe_executor_view_preview(execution_model, app_model, target, stored_rows) do
      {:ok, _preview} -> true
      :skip -> false
    end
  end

  def stored_view_output_missing_executor_drawables?(
        _execution_model,
        _app_model,
        _target,
        _rows
      ),
      do: false

  @doc false
  @spec maybe_executor_view_preview(
          Types.execution_model(),
          Types.app_model(),
          Types.surface_target(),
          Types.runtime_view_nodes()
        ) :: {:ok, Types.preview_view_derivation()} | :skip
  def maybe_executor_view_preview(execution_model, app_model, target, stored_rows)
      when is_map(execution_model) and is_map(app_model) and is_list(stored_rows) do
    if RuntimeArtifacts.versioned_elmx_artifacts?(execution_model) and stored_rows != [] do
      case executor_view_preview(execution_model, app_model, target) do
        {:ok, %{view_output: fresh_rows} = preview} ->
          stored = normalize_view_output(stored_rows)
          fresh = normalize_view_output(fresh_rows)

          if should_refresh_executor_view_preview?(app_model, stored, fresh) do
            {:ok, preview}
          else
            :skip
          end

        _ ->
          :skip
      end
    else
      :skip
    end
  end

  def maybe_executor_view_preview(_execution_model, _app_model, _target, _stored_rows), do: :skip

  @doc false
  @spec should_refresh_executor_view_preview?(
          Types.app_model(),
          Types.runtime_view_nodes(),
          Types.runtime_view_nodes()
        ) :: boolean()
  def should_refresh_executor_view_preview?(app_model, stored, fresh)
      when is_map(app_model) and is_list(stored) and is_list(fresh) do
    not view_output_captured_for_model?(app_model) or
      missing_supplemental_drawables?(stored, fresh) or
      view_output_scene_signature(stored) != view_output_scene_signature(fresh)
  end

  @style_view_output_kinds ~w(
    clear push_context pop_context stroke_width antialiased stroke_color fill_color text_color
    compositing_mode
  )

  @spec view_output_scene_signature(Types.runtime_view_nodes()) :: [term()]
  defp view_output_scene_signature(rows) when is_list(rows) do
    rows
    |> Enum.flat_map(&view_output_scene_tokens/1)
    |> Enum.sort()
  end

  @spec view_output_scene_tokens(Types.view_output_row()) :: [term()]
  defp view_output_scene_tokens(row) when is_map(row) do
    kind = to_string(Map.get(row, "kind") || Map.get(row, :kind) || "")

    if kind in @style_view_output_kinds or kind == "" do
      []
    else
      [view_output_scene_token(kind, row)]
    end
  end

  defp view_output_scene_tokens(_), do: []

  @spec view_output_scene_token(String.t(), Types.view_output_row()) :: term()
  defp view_output_scene_token("text", row),
    do:
      {:text, Map.get(row, "text"), view_output_row_int(row, "x", 0),
       view_output_row_int(row, "y", 0)}

  defp view_output_scene_token("text_label", row),
    do:
      {:text_label, Map.get(row, "text"), view_output_row_int(row, "x", 0),
       view_output_row_int(row, "y", 0)}

  defp view_output_scene_token("text_int", row),
    do:
      {:text_int, Map.get(row, "text"), view_output_row_int(row, "x", 0),
       view_output_row_int(row, "y", 0)}

  defp view_output_scene_token("bitmap_in_rect", row),
    do:
      {:bitmap_in_rect, view_output_row_int(row, "bitmap_id", 0),
       view_output_row_int(row, "x", 0), view_output_row_int(row, "y", 0),
       view_output_row_int(row, "w", 0), view_output_row_int(row, "h", 0)}

  defp view_output_scene_token("rotated_bitmap", row),
    do:
      {:rotated_bitmap, view_output_row_int(row, "bitmap_id", 0),
       view_output_row_int(row, "center_x", 0), view_output_row_int(row, "center_y", 0)}

  defp view_output_scene_token("bitmap_sequence_at", row),
    do:
      {:bitmap_sequence_at, view_output_row_int(row, "animation_id", 0),
       view_output_row_int(row, "x", 0), view_output_row_int(row, "y", 0)}

  defp view_output_scene_token("vector_at", row),
    do:
      {:vector_at, view_output_row_int(row, "vector_id", 0), view_output_row_int(row, "x", 0),
       view_output_row_int(row, "y", 0)}

  defp view_output_scene_token("vector_sequence_at", row),
    do:
      {:vector_sequence_at, view_output_row_int(row, "vector_id", 0),
       view_output_row_int(row, "x", 0), view_output_row_int(row, "y", 0)}

  defp view_output_scene_token(kind, row),
    do: {String.to_atom(kind), stable_term_sha256(row)}

  @spec preview_screen_dimensions(Types.inner_runtime_model()) ::
          {non_neg_integer(), non_neg_integer()}
  defp preview_screen_dimensions(model) when is_map(model) do
    {
      positive_dimension(Map.get(model, "screenW") || Map.get(model, :screenW)),
      positive_dimension(Map.get(model, "screenH") || Map.get(model, :screenH))
    }
  end

  @spec positive_dimension(term()) :: non_neg_integer()
  defp positive_dimension(value) when is_integer(value) and value > 0, do: value
  defp positive_dimension(value) when is_float(value) and value > 0, do: trunc(value)
  defp positive_dimension(_), do: 0

  @spec zero_geometry_positioned_rows?(Types.runtime_view_nodes()) :: boolean()
  defp zero_geometry_positioned_rows?(rows) when is_list(rows) do
    positioned =
      Enum.filter(rows, fn row ->
        is_map(row) and Map.get(row, "kind") in @positioned_view_output_kinds
      end)

    positioned != [] and Enum.all?(positioned, &zero_geometry_positioned_row?/1)
  end

  defp zero_geometry_positioned_rows?(_), do: false

  @spec zero_geometry_positioned_row?(Types.view_output_row()) :: boolean()
  defp zero_geometry_positioned_row?(%{"kind" => "circle"} = row),
    do: zero_coords?(row, ["cx", "cy"]) and zero_coords?(row, ["r"])

  defp zero_geometry_positioned_row?(%{"kind" => "fill_circle"} = row),
    do: zero_coords?(row, ["cx", "cy"]) and zero_coords?(row, ["r"])

  defp zero_geometry_positioned_row?(%{"kind" => kind} = row)
       when kind in ["line", "text", "text_label", "round_rect", "fill_rect", "rect", "pixel"],
       do: zero_coords?(row, ["x", "y"])

  defp zero_geometry_positioned_row?(%{"kind" => kind} = row)
       when kind in ["vector_at", "vector_sequence_at", "bitmap_sequence_at"],
       do: zero_coords?(row, ["x", "y"])

  defp zero_geometry_positioned_row?(_), do: false

  @spec zero_coords?(Types.view_output_row(), [String.t()]) :: boolean()
  defp zero_coords?(row, keys) when is_map(row) and is_list(keys) do
    Enum.all?(keys, fn key ->
      case Map.get(row, key) do
        value when is_integer(value) -> value == 0
        _ -> true
      end
    end)
  end

  @placeholder_view_tree_types ~w(root unknown previewUnavailable empty)

  @doc false
  @spec placeholder_view_tree?(Types.view_output_tree() | nil) :: boolean()
  def placeholder_view_tree?(%{"type" => type}) when is_binary(type),
    do: type in @placeholder_view_tree_types

  def placeholder_view_tree?(%{type: type}) when is_atom(type),
    do: Atom.to_string(type) in @placeholder_view_tree_types

  def placeholder_view_tree?(_), do: false

  @spec introspect_parser_view_tree(Types.execution_model(), Types.view_output_tree()) ::
          Types.view_output_tree()
  def introspect_parser_view_tree(execution_model, view_tree) when is_map(execution_model) do
    case introspect_view_tree(RuntimeArtifacts.introspect(execution_model)) do
      %{} = tree = introspect_tree ->
        if placeholder_view_tree?(introspect_tree), do: %{}, else: tree

      _ ->
        if placeholder_view_tree?(view_tree), do: %{}, else: view_tree
    end
  end

  def introspect_view_tree(%{} = introspect), do: Map.get(introspect, "view_tree") || %{}
  def introspect_view_tree(_), do: %{}

  @spec screen_dimensions_for_view_preview(Types.execution_model()) ::
          Types.screen_dimension_patch()
  def screen_dimensions_for_view_preview(execution_model) when is_map(execution_model) do
    %{
      "screenW" =>
        Map.get(execution_model, "screen_width") ||
          Map.get(execution_model, "screenW") ||
          get_in(execution_model, ["launch_context", "screen", "width"]),
      "screenH" =>
        Map.get(execution_model, "screen_height") ||
          Map.get(execution_model, "screenH") ||
          get_in(execution_model, ["launch_context", "screen", "height"])
    }
    |> Enum.reject(fn {_key, value} -> not is_integer(value) end)
    |> Map.new()
  end

  @spec runtime_view_output_tree(
          Types.app_model(),
          Types.surface_target(),
          Types.view_output_tree() | nil,
          keyword()
        ) :: Types.view_output_tree() | nil
  def runtime_view_output_tree(model, target, runtime_view_tree, opts)
      when is_map(model) and target in [:watch, :companion, :phone] and is_list(opts) do
    case RuntimeViewOutput.tree(model, target) do
      %{} = tree ->
        tree

      nil ->
        case Keyword.get(opts, :execution_model) do
          %{} = execution_model ->
            derive_preview_view_output(
              execution_model,
              runtime_view_tree || %{},
              RuntimeArtifacts.preview_runtime_model(model)
            )
            |> Map.get(:view_output, [])
            |> case do
              [] ->
                nil

              rows ->
                RuntimeViewOutput.tree(Map.put(model, "runtime_view_output", rows), target)
            end

          _ ->
            nil
        end
    end
  end

  @spec render_view_after_update(
          Types.view_output_tree() | nil,
          Types.view_output_tree() | nil,
          Types.surface_target(),
          String.t(),
          String.t(),
          Types.app_model(),
          keyword()
        ) :: Types.view_output_tree()
  def render_view_after_update(
        runtime_view_tree,
        previous_view_tree,
        target,
        message,
        trigger,
        model,
        opts
      )

  def render_view_after_update(
        runtime_view_tree,
        previous_view_tree,
        target,
        message,
        trigger,
        model,
        opts
      )
      when target in [:watch, :companion, :phone] and is_binary(message) and is_binary(trigger) and
             is_map(model) and is_list(opts) do
    output_view_tree = runtime_view_output_tree(model, target, runtime_view_tree, opts)
    ei = RuntimeArtifacts.require_introspect(model)

    runtime_view_tree =
      if placeholder_view_tree?(runtime_view_tree), do: %{}, else: runtime_view_tree

    contract_view_tree =
      introspect_parser_view_tree(Keyword.get(opts, :execution_model, %{}), runtime_view_tree)

    base =
      cond do
        is_map(output_view_tree) ->
          output_view_tree

        concrete_runtime_view_tree?(runtime_view_tree, ei) ->
          runtime_view_tree

        concrete_runtime_view_tree?(contract_view_tree, ei) ->
          contract_view_tree

        parser_expression_view_tree?(runtime_view_tree, ei) ->
          preview_unavailable_view_tree(target, "runtime view did not produce drawable output")

        concrete_runtime_view_tree?(previous_view_tree, ei) ->
          previous_view_tree

        true ->
          preview_unavailable_view_tree(target, "no renderable view tree")
      end

    base = normalize_debugger_render_tree(base)

    children =
      case Map.get(base, "children") || Map.get(base, :children) do
        xs when is_list(xs) -> xs
        _ -> []
      end

    render_marker = %{
      "type" => "debuggerRenderStep",
      "label" => "#{source_root_for_target(target)}:#{message}",
      "trigger" => trigger,
      "model_entries" => map_size(model),
      "children" => []
    }

    base
    |> Map.put("children", [render_marker | children] |> Enum.take(24))
    |> Map.put("last_runtime_step_message", message)
    |> Map.put("last_runtime_trigger", trigger)
  end

  def render_view_after_update(
        _runtime_view_tree,
        previous_view_tree,
        target,
        _message,
        _trigger,
        _model,
        opts
      )
      when target in [:watch, :companion, :phone] and is_list(opts) do
    default_view_tree = Keyword.get(opts, :default_view_tree, %{})

    if is_map(previous_view_tree) and map_size(previous_view_tree) > 0,
      do: previous_view_tree,
      else: default_view_tree
  end

  @spec normalize_debugger_render_tree(Types.view_output_tree()) :: Types.view_output_tree()
  def normalize_debugger_render_tree(%{"type" => "Window"} = tree) do
    window =
      tree
      |> Map.put("type", "window")
      |> Map.put_new("label", "")

    %{"type" => "windowStack", "label" => "", "children" => [window]}
  end

  def normalize_debugger_render_tree(%{"type" => "WindowStack"} = tree) do
    tree
    |> Map.put("type", "windowStack")
    |> Map.put_new("label", "")
  end

  def normalize_debugger_render_tree(tree), do: tree

  @spec concrete_runtime_view_tree?(Types.view_output_tree(), Types.elm_introspect()) :: boolean()
  def concrete_runtime_view_tree?(%{"type" => _} = tree, ei) when is_map(ei) do
    introspect_view_usable?(tree, ei) and not parser_expression_view_tree?(tree, ei)
  end

  def concrete_runtime_view_tree?(_tree, _ei), do: false

  @spec parser_expression_view_tree?(Types.view_output_tree(), Types.elm_introspect()) ::
          boolean()
  def parser_expression_view_tree?(tree, ei) when is_map(tree) and is_map(ei),
    do: ElmEx.DebuggerContract.parser_expression_view_tree_node?(tree, ei)

  def parser_expression_view_tree?(_tree, _ei), do: false
  @spec introspect_view_usable?(Types.view_output_tree(), Types.elm_introspect()) :: boolean()
  def introspect_view_usable?(%{"type" => "unknown", "children" => []}, _ei), do: false

  def introspect_view_usable?(%{"type" => type}, _ei)
      when is_binary(type) and type in @placeholder_view_tree_types,
      do: false

  def introspect_view_usable?(%{"type" => type} = tree, ei) when is_binary(type) do
    not unresolved_parser_view_root?(tree, ei)
  end

  def introspect_view_usable?(%{"children" => children}, _ei)
      when is_list(children) and children != [],
      do: true

  def introspect_view_usable?(_tree, _ei), do: false

  @draw_op_types ~w(
    clear fillRect rect roundRect line circle fillCircle pixel
    drawVectorAt drawVectorSequenceAt drawBitmapInRect drawBitmapSequenceAt
    drawRotatedBitmap arc fillRadial text textLabel group
    path pathFilled pathOutline pathOutlineOpen
  )

  @spec view_tree_has_draw_ops?(Types.view_output_tree()) :: boolean()
  def view_tree_has_draw_ops?(tree) when is_map(tree) do
    type =
      tree
      |> Map.get("type", Map.get(tree, :type, ""))
      |> to_string()

    type in @draw_op_types or
      tree
      |> Map.get("children", Map.get(tree, :children, []))
      |> List.wrap()
      |> Enum.any?(fn
        child when is_map(child) -> view_tree_has_draw_ops?(child)
        _ -> false
      end)
  end

  def view_tree_has_draw_ops?(_), do: false

  @spec unresolved_parser_view_root?(Types.view_output_tree(), Types.elm_introspect()) ::
          boolean()
  def unresolved_parser_view_root?(tree, ei) when is_map(tree) and is_map(ei),
    do: ElmEx.DebuggerContract.parser_expression_view_tree_node?(tree, ei)

  def unresolved_parser_view_root?(_tree, _ei), do: false

  @spec refresh_runtime_fingerprints(
          Types.execution_model(),
          Types.app_model(),
          Types.view_output_tree()
        ) :: Types.execution_model()
  def refresh_runtime_fingerprints(model, runtime_model, view_tree)
      when is_map(model) and is_map(runtime_model) do
    runtime = Map.get(model, "runtime_execution")
    runtime_mode = Map.get(model, "runtime_execution_mode")
    runtime_model_source = Map.get(model, "runtime_model_source")
    runtime_view_tree_source = Map.get(model, "runtime_view_tree_source")

    if runtime_mode == "runtime_executed" or (is_map(runtime) and map_size(runtime) > 0) or
         map_size(runtime_model) > 0 do
      runtime = if is_map(runtime), do: runtime, else: %{}
      runtime_view_tree = if is_map(view_tree), do: view_tree, else: %{}

      runtime =
        runtime
        |> Map.put("runtime_model_entry_count", map_size(runtime_model))
        |> Map.put("view_tree_node_count", view_tree_node_count(runtime_view_tree))
        |> Map.put("runtime_model_sha256", stable_term_sha256(runtime_model))
        |> Map.put("view_tree_sha256", stable_term_sha256(runtime_view_tree))
        |> maybe_put_runtime_source("runtime_model_source", runtime_model_source)
        |> maybe_put_runtime_source("view_tree_source", runtime_view_tree_source)

      model
      |> Map.put("runtime_execution", runtime)
      |> Map.put("runtime_model_sha256", runtime["runtime_model_sha256"])
      |> Map.put("runtime_view_tree_sha256", runtime["view_tree_sha256"])
    else
      model
    end
  end

  @spec maybe_put_runtime_source(Types.view_output_tree(), String.t(), String.t() | nil) ::
          Types.view_output_tree()
  def maybe_put_runtime_source(runtime, _key, value) when not is_binary(value), do: runtime
  def maybe_put_runtime_source(runtime, _key, value) when value == "", do: runtime
  def maybe_put_runtime_source(runtime, key, value), do: Map.put(runtime, key, value)

  @spec view_tree_node_count(Types.view_output_tree() | [Types.view_output_tree()]) ::
          non_neg_integer()
  def view_tree_node_count(%{"children" => children}) when is_list(children) do
    1 +
      Enum.reduce(children, 0, fn child, acc ->
        if is_map(child), do: acc + view_tree_node_count(child), else: acc
      end)
  end

  def view_tree_node_count(%{children: children}) when is_list(children) do
    1 +
      Enum.reduce(children, 0, fn child, acc ->
        if is_map(child), do: acc + view_tree_node_count(child), else: acc
      end)
  end

  def view_tree_node_count(%{}), do: 1
  def view_tree_node_count(_), do: 0

  @spec stable_term_sha256(Types.normalized_export_term() | list()) :: String.t()
  def stable_term_sha256(term) do
    :crypto.hash(:sha256, :erlang.term_to_binary(term))
    |> Base.encode16(case: :lower)
  end

  @spec executor_module() :: module()
  defp executor_module do
    Application.get_env(:ide, Ide.Debugger, [])
    |> Keyword.get(:runtime_executor_module, RuntimeExecutor)
  end

  @spec source_root_for_target(Types.surface_target()) :: String.t()
  defp source_root_for_target(:watch), do: "watch"
  defp source_root_for_target(:companion), do: "phone"
  defp source_root_for_target(:phone), do: "phone"

  @spec integer_or_zero(Types.wire_input()) :: non_neg_integer()
  defp integer_or_zero(value) when is_integer(value) and value >= 0, do: value

  defp integer_or_zero(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _} when parsed >= 0 -> parsed
      _ -> 0
    end
  end

  defp integer_or_zero(_), do: 0

  @spec preview_unavailable_view_tree(Types.surface_target(), String.t()) ::
          Types.view_output_tree()
  defp preview_unavailable_view_tree(target, reason) do
    %{
      "type" => "previewUnavailable",
      "label" => reason,
      "target" => source_root_for_target(target),
      "children" => []
    }
  end
end
