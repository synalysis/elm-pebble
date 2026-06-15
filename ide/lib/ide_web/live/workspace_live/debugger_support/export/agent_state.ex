defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Export.AgentState do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types

  @type debugger_state_export_ctx :: Types.debugger_state_export_ctx()
  @type json_export_input :: Types.json_export_input()

  @spec copy_json(json_export_input()) :: String.t()
  def copy_json(term) do
    case Jason.encode(term, pretty: true) do
      {:ok, json} -> json
      {:error, _reason} -> Jason.encode!(inspect(term), pretty: true)
    end
  end

  @doc """
  Single markdown document for assistants: meta, timeline text, and JSON blocks for models and rendered tree.
  """
  @spec debugger_agent_state_markdown(debugger_state_export_ctx()) :: String.t()
  def debugger_agent_state_markdown(%{} = ctx) do
    format = Map.get(ctx, :format_version, "elm-pebble.debugger_state.v1")
    name = Map.get(ctx, :project_name, "")
    slug = Map.get(ctx, :project_slug, "")
    timeline_mode = Map.get(ctx, :timeline_mode, "")

    timeline =
      Map.get(ctx, :timeline_text, "") |> blank_fallback("(no timeline rows for this view)")

    watch_j = Map.get(ctx, :watch_model_json, "{}")
    comp_j = Map.get(ctx, :companion_model_json, "{}")
    view_j = Map.get(ctx, :rendered_view_json, "null")

    running = session_field(ctx, :session_running)
    evc = session_field(ctx, :session_event_count)
    cur = session_field(ctx, :debugger_cursor_seq)
    sel = session_field(ctx, :selected_timeline_seq)
    profile = session_field(ctx, :watch_profile_id)
    warnings = Map.get(ctx, :runtime_model_warnings)

    warnings_section =
      case warnings do
        w when is_binary(w) and w != "" ->
          """

          ## Runtime model warnings

          #{w}
          """

        _ ->
          ""
      end

    """
    # IDE debugger state export

    Use this document as context for an assistant. Sections mirror the Debugger page (live watch view / models).

    ## Meta

    - **format**: `#{format}`
    - **project**: #{name} (`#{slug}`)
    - **timeline_mode** (visible filter): `#{timeline_mode}`
    - **selected_timeline_seq**: #{sel}
    - **debugger_cursor_seq** (event cursor): #{cur}
    - **session_running**: #{running}
    - **session_event_count**: #{evc}
    - **watch_profile_id**: #{profile}

    ## Timeline

    #{timeline}
    #{warnings_section}

    ## Watch model

    ```json
    #{watch_j}
    ```

    ## Companion model

    ```json
    #{comp_j}
    ```

    ## Rendered view (watch, live panel)

    ```json
    #{view_j}
    ```
    """
    |> String.trim()
  end

  defp blank_fallback(s, fallback) when is_binary(s) do
    if String.trim(s) == "", do: fallback, else: s
  end

  defp blank_fallback(_, fallback), do: fallback

  defp session_field(ctx, key) do
    case Map.get(ctx, key) do
      nil -> "—"
      false -> "false"
      true -> "true"
      n when is_integer(n) -> Integer.to_string(n)
      other -> inspect(other)
    end
  end
end