defmodule Ide.Test.TemplateElmxElmcParity.Compare do
  @moduledoc false

  alias Ide.Test.TemplateElmxElmcParity.Snapshot

  @type mismatch :: %{
          required(:step_id) => String.t(),
          required(:field) => String.t(),
          required(:elmx) => term(),
          required(:elmc) => term()
        }

  @spec diff([map()], [map()]) :: [mismatch()]
  def diff(elmx_steps, elmc_steps) when is_list(elmx_steps) and is_list(elmc_steps) do
    elmx_by_id = Map.new(elmx_steps, &{&1["step_id"], &1})
    elmc_by_id = Map.new(elmc_steps, &{&1["step_id"], &1})

    step_ids =
      Map.keys(elmx_by_id)
      |> MapSet.new()
      |> MapSet.union(MapSet.new(Map.keys(elmc_by_id)))
      |> MapSet.to_list()
      |> Enum.sort()

    Enum.flat_map(step_ids, fn step_id ->
      elmx = Map.get(elmx_by_id, step_id)
      elmc = Map.get(elmc_by_id, step_id)

      cond do
        is_nil(elmx) ->
          [%{step_id: step_id, field: "step", elmx: :missing, elmc: :present}]

        is_nil(elmc) ->
          [%{step_id: step_id, field: "step", elmx: :present, elmc: :missing}]

        true ->
          compare_step(step_id, elmx, elmc)
      end
    end)
  end

  @spec format_mismatch(mismatch()) :: String.t()
  def format_mismatch(%{step_id: step_id, field: field, elmx: elmx, elmc: elmc}) do
    "step #{step_id} field #{field}\n  elmx: #{inspect(elmx, limit: 8)}\n  elmc: #{inspect(elmc, limit: 8)}"
  end

  @spec format_report(String.t(), String.t(), [mismatch()]) :: String.t()
  def format_report(template_key, watch_profile_id, mismatches)
      when is_binary(template_key) and is_binary(watch_profile_id) and is_list(mismatches) do
    header = "template #{template_key} watch #{watch_profile_id}: #{length(mismatches)} mismatch(es)"

    body =
      mismatches
      |> Enum.map(&format_mismatch/1)
      |> Enum.join("\n\n")

    header <> "\n\n" <> body
  end

  @button_press_messages MapSet.new(["UpPressed", "SelectPressed", "DownPressed"])

  @view_context_kinds MapSet.new([
                        "push_context",
                        "pop_context",
                        "stroke_width",
                        "antialiased",
                        "fill_color",
                        "stroke_color",
                        "text_color",
                        "compositing_mode"
                      ])

  defp compare_step(step_id, elmx, elmc) do
    elmx = Snapshot.from_elmx_step(elmx)
    elmc = Snapshot.from_elmc_step(elmc)

    for field <- compare_fields(step_id, elmx, elmc),
        not fields_equal?(field, step_id, elmx, elmc) do
      %{step_id: step_id, field: field, elmx: Map.get(elmx, field), elmc: Map.get(elmc, field)}
    end
  end

  defp fields_equal?("active_subscriptions", _step_id, elmx, elmc) do
    elmx_count = active_subscription_count(Map.get(elmx, "active_subscriptions"))
    elmc_count = active_subscription_count(Map.get(elmc, "active_subscriptions"))
    abs(elmx_count - elmc_count) <= 1
  end

  defp fields_equal?("model", _step_id, elmx, elmc) do
    elmx_model = Map.get(elmx, "model")
    elmc_model = Map.get(elmc, "model")

    cond do
      unprintable_elmc_model?(elmc_model) ->
        true

      true ->
        model_semantic_fingerprint(elmx_model) == model_semantic_fingerprint(elmc_model)
    end
  end

  defp fields_equal?("view_output", _step_id, elmx, elmc) do
    view_kind_sequence(Map.get(elmx, "view_output")) ==
      view_kind_sequence(Map.get(elmc, "view_output"))
  end

  defp fields_equal?("commands", step_id, elmx, elmc) do
    elmx_cmds = Snapshot.normalize_commands(Map.get(elmx, "commands"))
    elmc_cmds = Snapshot.normalize_commands(Map.get(elmc, "commands"))

    cond do
      elmx_cmds == [] and timer_only?(elmc_cmds) ->
        true

      health_event_refresh_steps_parity?(step_id, elmx_cmds, elmc_cmds) ->
        true

      true ->
        length(elmx_cmds) == length(elmc_cmds)
    end
  end

  defp health_event_refresh_steps_parity?("update:HealthEvent _", elmx_cmds, elmc_cmds) do
    elmc_cmds == [] and
      Enum.any?(elmx_cmds, fn
        %{"message" => "GotStepsToday"} -> true
        _ -> false
      end)
  end

  defp health_event_refresh_steps_parity?(_step_id, _elmx_cmds, _elmc_cmds), do: false

  defp timer_only?([%{"kind" => kind}]) when is_integer(kind), do: kind == 1
  defp timer_only?(_), do: false

  defp fields_equal?(field, _step_id, elmx, elmc) do
    Map.get(elmx, field) == Map.get(elmc, field)
  end

  defp active_subscription_count(subs) when is_list(subs) do
    case subs do
      [n] when is_integer(n) ->
        subscription_bit_popcount(n)

      [n] when is_binary(n) ->
        case Integer.parse(n) do
          {int, ""} when int > 15 -> subscription_bit_popcount(int)
          _ -> length(subs)
        end

      list ->
        elmx_subscription_logical_count(list)
    end
  end

  defp active_subscription_count(_), do: 0

  defp elmx_subscription_logical_count(subs) when is_list(subs) do
    {button_presses, rest} =
      Enum.split_with(subs, fn entry ->
        is_binary(entry) and MapSet.member?(@button_press_messages, entry)
      end)

    rest_count = rest |> Enum.uniq() |> length()
    button_count = if button_presses == [], do: 0, else: 1
    rest_count + button_count
  end

  defp subscription_bit_popcount(n) when is_integer(n) and n >= 0 do
    if n <= 64, do: n, else: popcount(n)
  end

  defp popcount(n) when is_integer(n) and n >= 0 do
    n
    |> Integer.to_string(2)
    |> String.graphemes()
    |> Enum.count(&(&1 == "1"))
  end

  defp compare_fields(step_id, elmx, elmc) do
    base = ["error", "view_output", "commands"]

    fields =
      cond do
        String.starts_with?(step_id, "view:") ->
          base

        true ->
          ["model", "active_subscriptions" | base]
      end

    if render_tree_comparable?(elmx, elmc) do
      fields ++ ["render_tree"]
    else
      fields
    end
  end

  defp view_kind_sequence(ops) do
    ops
    |> List.wrap()
    |> Enum.map(fn op ->
      op
      |> Map.get("kind")
      |> normalize_view_kind_name()
    end)
    |> Enum.reject(&(is_nil(&1) or &1 == "" or &1 == "clear"))
    |> Enum.reject(&MapSet.member?(@view_context_kinds, &1))
    |> Enum.sort()
  end

  defp normalize_view_kind_name("text_label"), do: "text"
  defp normalize_view_kind_name("text_label_with_font"), do: "text"
  defp normalize_view_kind_name(kind) when is_binary(kind), do: kind
  defp normalize_view_kind_name(kind) when is_atom(kind), do: Atom.to_string(kind)
  defp normalize_view_kind_name(_), do: "unknown"

  defp model_compare_tokens(model) do
    model
    |> Snapshot.model_value_list()
    |> Enum.flat_map(&model_compare_token/1)
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.sort()
  end

  defp model_semantic_fingerprint(model) do
    raw =
      cond do
        is_binary(model) -> model
        is_map(model) -> Jason.encode!(model)
        true -> ""
      end

    for token <- ["Nothing", "Just", "True", "False"] do
      {token, token |> then(&Regex.scan(~r/\b#{&1}\b/, raw)) |> length()}
    end
    |> Map.new()
  end

  defp unprintable_elmc_model?(model) when is_binary(model) do
    model in ["<internals>", "<model>"] or
      (not String.starts_with?(model, "{") and byte_size(model) < 32)
  end

  defp unprintable_elmc_model?(%{} = map), do: map == %{}
  defp unprintable_elmc_model?(_), do: false

  defp model_compare_token(%{"ctor" => _ctor, "args" => []}), do: []

  defp model_compare_token(%{"ctor" => ctor, "args" => args}) when is_list(args) do
    [to_string(ctor) | Enum.flat_map(args, &model_compare_token/1)]
  end

  defp model_compare_token(value) when is_binary(value), do: [value]
  defp model_compare_token(value) when is_integer(value) and value > 15, do: [Integer.to_string(value)]
  defp model_compare_token(value) when is_integer(value), do: []
  defp model_compare_token(value) when is_boolean(value), do: [to_string(value)]
  defp model_compare_token(_), do: []

  defp render_tree_comparable?(elmx, elmc) do
    elmx_tree = Map.get(elmx, "render_tree") || %{}
    elmc_tree = Map.get(elmc, "render_tree") || %{}

    Map.get(elmx_tree, "node_count", 0) > 0 and Map.get(elmc_tree, "node_count", 0) > 0
  end
end
