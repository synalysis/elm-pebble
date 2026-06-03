defmodule Elmc.Backend.Pebble.IRAnalysis do
  @moduledoc false

  alias ElmEx.IR
  alias Elmc.Backend.Pebble.Util

  @type msg_constructor_pair :: {String.t(), non_neg_integer()}

  @spec msg_constructors(ElmEx.IR.t(), String.t()) :: [msg_constructor_pair()]
  def msg_constructors(ir, entry_module) do
    module = Enum.find(ir.modules, &(&1.name == entry_module))

    union =
      if module do
        module.unions["Msg"]
      else
        nil
      end

    tags = if union, do: union.tags, else: %{}

    tags
    |> Map.to_list()
    |> Enum.sort_by(fn {_name, tag} -> tag end)
  end

  @spec msg_constructor_arities(ElmEx.IR.t(), String.t()) :: %{
          optional(String.t()) => non_neg_integer()
        }
  def msg_constructor_arities(ir, entry_module) do
    module = Enum.find(ir.modules, &(&1.name == entry_module))
    union = if module, do: module.unions["Msg"], else: nil
    constructors = if union, do: Map.get(union, :constructors, []), else: []

    constructors
    |> Enum.reduce(%{}, fn constructor, acc ->
      name = Map.get(constructor, :name)
      spec = Map.get(constructor, :arg)

      if is_binary(name) and name != "" do
        Map.put(acc, name, Util.payload_arity_for_spec(spec))
      else
        acc
      end
    end)
  end

  @spec msg_constructor_payload_specs(ElmEx.IR.t(), String.t()) :: %{
          optional(String.t()) => String.t() | nil
        }
  def msg_constructor_payload_specs(ir, entry_module) do
    module = Enum.find(ir.modules, &(&1.name == entry_module))
    union = if module, do: module.unions["Msg"], else: nil
    constructors = if union, do: Map.get(union, :constructors, []), else: []

    constructors
    |> Map.new(fn constructor ->
      {Map.get(constructor, :name), Map.get(constructor, :arg)}
    end)
  end

  @spec random_generate_target_tag(IR.t(), [{String.t(), non_neg_integer()}]) :: integer()
  def random_generate_target_tag(%IR{} = ir, msg_constructors) do
    ir.modules
    |> Enum.flat_map(fn mod -> Map.get(mod, :declarations, []) end)
    |> Enum.flat_map(fn declaration ->
      random_generate_target_names(Map.get(declaration, :expr) || Map.get(declaration, :body))
    end)
    |> Enum.find_value(-1, fn
      {:tag, tag} when is_integer(tag) ->
        tag

      name ->
        Enum.find_value(msg_constructors, fn
          {^name, tag} -> tag
          _ -> nil
        end)
    end)
  end

  defp random_generate_target_names(%{
         op: :qualified_call,
         target: target,
         args: [to_msg, _generator]
       })
       when target in ["Random.generate", "Elm.Kernel.Random.generate"] do
    callback_tagger_names(to_msg)
  end

  defp random_generate_target_names(%{} = node) do
    node
    |> Map.values()
    |> Enum.flat_map(&random_generate_target_names/1)
  end

  defp random_generate_target_names(list) when is_list(list),
    do: Enum.flat_map(list, &random_generate_target_names/1)

  defp random_generate_target_names(_), do: []

  defp callback_tagger_names(%{op: :var, name: name}) when is_binary(name), do: [name]

  defp callback_tagger_names(%{op: :int_literal, value: tag}) when is_integer(tag),
    do: [{:tag, tag}]

  defp callback_tagger_names(%{op: :qualified_var, target: target})
       when is_binary(target) do
    [target |> String.split(".") |> List.last()]
  end

  defp callback_tagger_names(%{op: :qualified_call, target: target, args: []})
       when is_binary(target) do
    [target |> String.split(".") |> List.last()]
  end

  defp callback_tagger_names(_), do: []

  @spec health_event_target_tag(IR.t(), [{String.t(), non_neg_integer()}]) :: integer()
  def health_event_target_tag(%IR{} = ir, msg_constructors) do
    ir.modules
    |> Enum.flat_map(fn mod -> Map.get(mod, :declarations, []) end)
    |> Enum.flat_map(fn declaration ->
      health_event_target_names(Map.get(declaration, :expr) || Map.get(declaration, :body))
    end)
    |> Enum.find_value(-1, fn
      {:tag, tag} when is_integer(tag) ->
        tag

      name ->
        Enum.find_value(msg_constructors, fn
          {^name, tag} -> tag
          _ -> nil
        end)
    end)
  end

  defp health_event_target_names(%{op: :qualified_call, target: target, args: [to_msg]})
       when target in ["Pebble.Health.onEvent", "Elm.Kernel.PebbleWatch.onHealthEvent"] do
    callback_tagger_names(to_msg)
  end

  defp health_event_target_names(%{} = node) do
    node
    |> Map.values()
    |> Enum.flat_map(&health_event_target_names/1)
  end

  defp health_event_target_names(list) when is_list(list),
    do: Enum.flat_map(list, &health_event_target_names/1)

  defp health_event_target_names(_), do: []

  @spec app_focus_change_target_tag(IR.t(), [{String.t(), non_neg_integer()}]) :: integer()
  def app_focus_change_target_tag(%IR{} = ir, msg_constructors) do
    target_tag_from_subscription(
      ir,
      msg_constructors,
      ["Pebble.AppFocus.onChange", "Elm.Kernel.PebbleWatch.onAppFocusChange"]
    )
  end

  @spec compass_change_target_tag(IR.t(), [{String.t(), non_neg_integer()}]) :: integer()
  def compass_change_target_tag(%IR{} = ir, msg_constructors) do
    target_tag_from_subscription(
      ir,
      msg_constructors,
      ["Pebble.Compass.onChange", "Elm.Kernel.PebbleWatch.onCompassChange"]
    )
  end

  @spec dictation_status_target_tag(IR.t(), [{String.t(), non_neg_integer()}]) :: integer()
  def dictation_status_target_tag(%IR{} = ir, msg_constructors) do
    target_tag_from_subscription(
      ir,
      msg_constructors,
      ["Pebble.Dictation.onStatus", "Elm.Kernel.PebbleWatch.onDictationStatus"]
    )
  end

  @spec dictation_result_target_tag(IR.t(), [{String.t(), non_neg_integer()}]) :: integer()
  def dictation_result_target_tag(%IR{} = ir, msg_constructors) do
    target_tag_from_subscription(
      ir,
      msg_constructors,
      ["Pebble.Dictation.onResult", "Elm.Kernel.PebbleWatch.onDictationResult"]
    )
  end

  @spec unobstructed_will_change_target_tag(IR.t(), [{String.t(), non_neg_integer()}]) ::
          integer()
  def unobstructed_will_change_target_tag(%IR{} = ir, msg_constructors) do
    target_tag_from_subscription(
      ir,
      msg_constructors,
      [
        "Pebble.UnobstructedArea.onWillChange",
        "Elm.Kernel.PebbleWatch.onUnobstructedWillChange"
      ]
    )
  end

  @spec unobstructed_changing_target_tag(IR.t(), [{String.t(), non_neg_integer()}]) :: integer()
  def unobstructed_changing_target_tag(%IR{} = ir, msg_constructors) do
    target_tag_from_subscription(
      ir,
      msg_constructors,
      [
        "Pebble.UnobstructedArea.onChanging",
        "Elm.Kernel.PebbleWatch.onUnobstructedChanging"
      ]
    )
  end

  @spec unobstructed_did_change_target_tag(IR.t(), [{String.t(), non_neg_integer()}]) :: integer()
  def unobstructed_did_change_target_tag(%IR{} = ir, msg_constructors) do
    target_tag_from_subscription(
      ir,
      msg_constructors,
      [
        "Pebble.UnobstructedArea.onDidChange",
        "Elm.Kernel.PebbleWatch.onUnobstructedDidChange"
      ]
    )
  end

  @spec unobstructed_bounds_target_tag(IR.t(), [{String.t(), non_neg_integer()}]) :: integer()
  def unobstructed_bounds_target_tag(%IR{} = ir, msg_constructors) do
    target_tag_from_cmd(
      ir,
      msg_constructors,
      [
        "Pebble.UnobstructedArea.currentBounds",
        "Elm.Kernel.PebbleWatch.unobstructedCurrentBounds"
      ]
    )
  end

  @spec target_tag_from_cmd(IR.t(), [{String.t(), non_neg_integer()}], [String.t()]) :: integer()
  defp target_tag_from_cmd(%IR{} = ir, msg_constructors, targets) do
    ir.modules
    |> Enum.flat_map(fn mod -> Map.get(mod, :declarations, []) end)
    |> Enum.flat_map(fn declaration ->
      cmd_target_names(Map.get(declaration, :expr) || Map.get(declaration, :body), targets)
    end)
    |> Enum.find_value(-1, fn
      {:tag, tag} when is_integer(tag) -> tag
      name -> Enum.find_value(msg_constructors, fn {^name, tag} -> tag end)
    end)
  end

  defp cmd_target_names(%{op: :qualified_call, target: target, args: [to_msg]}, targets) do
    if target in targets, do: callback_tagger_names(to_msg), else: []
  end

  defp cmd_target_names(%{} = node, targets) do
    node |> Map.values() |> Enum.flat_map(&cmd_target_names(&1, targets))
  end

  defp cmd_target_names(list, targets) when is_list(list),
    do: Enum.flat_map(list, &cmd_target_names(&1, targets))

  defp cmd_target_names(_, _), do: []

  @spec target_tag_from_subscription(IR.t(), [{String.t(), non_neg_integer()}], [String.t()]) ::
          integer()
  defp target_tag_from_subscription(%IR{} = ir, msg_constructors, targets) do
    ir.modules
    |> Enum.flat_map(fn mod -> Map.get(mod, :declarations, []) end)
    |> Enum.flat_map(fn declaration ->
      subscription_target_names(
        Map.get(declaration, :expr) || Map.get(declaration, :body),
        targets
      )
    end)
    |> Enum.find_value(-1, fn
      {:tag, tag} when is_integer(tag) ->
        tag

      name ->
        Enum.find_value(msg_constructors, fn
          {^name, tag} -> tag
          _ -> nil
        end)
    end)
  end

  defp subscription_target_names(%{op: :qualified_call, target: target, args: [to_msg]}, targets) do
    if target in targets, do: callback_tagger_names(to_msg), else: []
  end

  defp subscription_target_names(%{} = node, targets) do
    node
    |> Map.values()
    |> Enum.flat_map(&subscription_target_names(&1, targets))
  end

  defp subscription_target_names(list, targets) when is_list(list),
    do: Enum.flat_map(list, &subscription_target_names(&1, targets))

  defp subscription_target_names(_, _), do: []

  @spec accel_config_from_ir(IR.t(), String.t()) :: map()
  def accel_config_from_ir(%IR{} = ir, _entry_module) do
    bindings = accel_config_bindings(ir)

    ir.modules
    |> Enum.flat_map(fn mod -> Map.get(mod, :declarations, []) end)
    |> Enum.reduce(%{samples_per_update: 1, sampling_hz: 25}, fn declaration, acc ->
      accel_config_from_node(
        Map.get(declaration, :expr) || Map.get(declaration, :body),
        acc,
        bindings
      )
    end)
  end

  defp accel_config_bindings(%IR{} = ir) do
    ir.modules
    |> Enum.flat_map(fn mod ->
      mod.declarations
      |> Enum.filter(fn decl -> Map.get(decl, :kind) in [:value, :function] end)
      |> Enum.flat_map(fn decl ->
        expr = Map.get(decl, :expr) || Map.get(decl, :body)

        case expr do
          %{op: :record_literal} = record ->
            [{decl.name, record}, {"#{mod.name}.#{decl.name}", record}]

          _ ->
            []
        end
      end)
    end)
    |> Map.new()
  end

  defp accel_config_from_node(
         %{op: :qualified_call, target: "Pebble.Accel.onData", args: [config | _]},
         acc,
         bindings
       ) do
    resolved = resolve_accel_config_expr(config, bindings)

    acc
    |> Map.put(
      :samples_per_update,
      accel_config_int(resolved, "samplesPerUpdate", acc[:samples_per_update])
    )
    |> Map.put(:sampling_hz, accel_config_sampling_hz(resolved, acc[:sampling_hz]))
  end

  defp accel_config_from_node(
         %{op: :qualified_call, target: "Elm.Kernel.PebbleWatch.onAccelData", args: [hz | _]},
         acc,
         _bindings
       )
       when is_integer(hz) or is_map(hz) do
    case hz do
      %{op: :int_literal, value: value} when is_integer(value) ->
        Map.put(acc, :sampling_hz, value)

      _ ->
        acc
    end
  end

  defp accel_config_from_node(%{} = node, acc, bindings) do
    node
    |> Map.values()
    |> Enum.reduce(acc, &accel_config_from_node(&1, &2, bindings))
  end

  defp accel_config_from_node(list, acc, bindings) when is_list(list),
    do: Enum.reduce(list, acc, &accel_config_from_node(&1, &2, bindings))

  defp accel_config_from_node(_, acc, _bindings), do: acc

  defp resolve_accel_config_expr(%{op: :var, name: name}, bindings) do
    Map.get(bindings, name, %{op: :unknown})
  end

  defp resolve_accel_config_expr(%{op: :qualified_var, target: target}, bindings) do
    target
    |> String.split(".")
    |> List.last()
    |> then(&Map.get(bindings, &1, %{op: :unknown}))
  end

  defp resolve_accel_config_expr(expr, _bindings), do: expr

  defp accel_config_int(%{op: :record_literal, fields: fields}, field, default)
       when is_list(fields) do
    case Enum.find(fields, &(&1.name == field)) do
      %{expr: %{op: :int_literal, value: value}} when is_integer(value) and value > 0 -> value
      _ -> default
    end
  end

  defp accel_config_int(%{op: :var, name: _name}, _field, default), do: default

  defp accel_config_int(_, _, default), do: default

  defp accel_config_sampling_hz(%{op: :record_literal, fields: fields}, default)
       when is_list(fields) do
    case Enum.find(fields, &(&1.name == "samplingRate")) do
      %{expr: %{op: :int_literal, value: value}} when value in 1..4 ->
        accel_sampling_hz_from_tag(value)

      %{expr: %{op: :int_literal, value: value}} when value in [10, 25, 50, 100] ->
        value

      %{expr: %{op: :qualified_var, target: target}} ->
        target |> String.split(".") |> List.last() |> accel_sampling_hz_from_name(default)

      %{expr: %{op: :qualified_ref, target: target}} ->
        target |> String.split(".") |> List.last() |> accel_sampling_hz_from_name(default)

      %{expr: %{op: :qualified_call, target: target, args: []}} ->
        target |> String.split(".") |> List.last() |> accel_sampling_hz_from_name(default)

      %{expr: %{op: :constructor_call, target: target, args: []}} when is_binary(target) ->
        target |> String.split(".") |> List.last() |> accel_sampling_hz_from_name(default)

      _ ->
        default
    end
  end

  defp accel_config_sampling_hz(_, default), do: default

  defp accel_sampling_hz_from_name("Hz10", _), do: 10
  defp accel_sampling_hz_from_name("Hz25", _), do: 25
  defp accel_sampling_hz_from_name("Hz50", _), do: 50
  defp accel_sampling_hz_from_name("Hz100", _), do: 100
  defp accel_sampling_hz_from_name("10", _), do: 10
  defp accel_sampling_hz_from_name("25", _), do: 25
  defp accel_sampling_hz_from_name("50", _), do: 50
  defp accel_sampling_hz_from_name("100", _), do: 100
  defp accel_sampling_hz_from_name(_, default), do: default

  defp accel_sampling_hz_from_tag(1), do: 10
  defp accel_sampling_hz_from_tag(2), do: 25
  defp accel_sampling_hz_from_tag(3), do: 50
  defp accel_sampling_hz_from_tag(4), do: 100
  defp accel_sampling_hz_from_tag(_), do: 25

  @spec phone_to_watch_msg_target([{String.t(), non_neg_integer()}], map()) :: integer()
  def phone_to_watch_msg_target(msg_constructors, payload_specs) do
    Enum.find_value(msg_constructors, -1, fn {name, tag} ->
      case Map.get(payload_specs, name) do
        "PhoneToWatch" -> tag
        "Companion.Types.PhoneToWatch" -> tag
        _ -> nil
      end
    end)
  end

  @spec constructor_name_for_tag([{String.t(), non_neg_integer()}], non_neg_integer()) ::
          String.t() | nil
  def constructor_name_for_tag(constructors, tag) when is_integer(tag) do
    Enum.find_value(constructors, fn
      {name, ^tag} -> name
      _ -> nil
    end)
  end

  @spec has_view?(ElmEx.IR.t(), String.t()) :: boolean()
  def has_view?(ir, entry_module) do
    ir.modules
    |> Enum.find(&(&1.name == entry_module))
    |> case do
      nil -> false
      mod -> Enum.any?(mod.declarations, &(&1.kind == :function and &1.name == "view"))
    end
  end

  @spec pick_tag([msg_constructor_pair()], [String.t()], keyword()) :: integer()
  def pick_tag(msg_constructors, names, opts \\ []) do
    fallback = Keyword.get(opts, :fallback, -1)

    Enum.find_value(names, fallback, fn name ->
      Enum.find_value(msg_constructors, fn
        {^name, tag} -> tag
        _ -> nil
      end)
    end)
  end

  @spec union_constructors(ElmEx.IR.t(), String.t(), String.t()) :: [
          {String.t(), non_neg_integer()}
        ]
  def union_constructors(ir, module_name, union_name) do
    ir.modules
    |> Enum.find(&(&1.name == module_name))
    |> case do
      nil ->
        []

      mod ->
        mod.unions
        |> Map.get(union_name, %{tags: %{}})
        |> Map.get(:tags, %{})
        |> Map.to_list()
        |> Enum.sort_by(fn {_ctor, tag} -> tag end)
    end
  end
end
