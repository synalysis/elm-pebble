defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Util do
  @moduledoc false
  @dialyzer :no_match

  alias Ide.Debugger.RuntimeArtifacts
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types
  @spec timeline_upper_seq([map()], Types.maybe_non_neg_integer()) :: non_neg_integer()
  def timeline_upper_seq(events, cursor_seq) do
    cond do
      is_integer(cursor_seq) ->
        cursor_seq

      events == [] ->
        0

      true ->
        events |> Enum.map(& &1.seq) |> Enum.max()
    end
  end

  @spec protocol_payload_field(map(), atom()) :: String.t() | nil
  def protocol_payload_field(payload, key) when is_map(payload) do
    str = Atom.to_string(key)
    v = Map.get(payload, key) || Map.get(payload, str)
    if is_binary(v), do: v
  end

  def protocol_payload_field(_payload, _key), do: nil

  @spec elm_value(Types.runtime_value()) :: String.t()
  def elm_value(%{} = value) do
    ctor = Map.get(value, "ctor") || Map.get(value, "$ctor")
    args = Map.get(value, "args") || Map.get(value, "$args") || []

    cond do
      is_binary(ctor) and args == [] ->
        ctor

      is_binary(ctor) and is_list(args) ->
        ([ctor] ++ Enum.map(args, &elm_value/1)) |> Enum.join(" ")

      true ->
        fields =
          value
          |> Enum.reject(fn {key, _field_value} -> key in ["ctor", "args", "$ctor", "$args"] end)
          |> Enum.sort_by(fn {key, _field_value} -> key end)
          |> Enum.map(fn {key, field_value} ->
            "#{elm_field_name(key)} = #{elm_value(field_value)}"
          end)
          |> Enum.join(", ")

        "{ #{fields} }"
    end
  end

  def elm_value(values) when is_list(values) do
    "[" <> Enum.map_join(values, ", ", &elm_value/1) <> "]"
  end

  def elm_value(value) when is_binary(value), do: inspect(value)
  def elm_value(true), do: "True"
  def elm_value(false), do: "False"
  def elm_value(nil), do: "null"
  def elm_value(value), do: to_string(value)

  @spec elm_field_name(map()) :: String.t()
  def elm_field_name(key) when is_binary(key), do: key
  def elm_field_name(key), do: to_string(key)

  @spec normalize_debugger_timeline_mode(Types.wire_input()) :: String.t()
  def normalize_debugger_timeline_mode("watch"), do: "watch"
  def normalize_debugger_timeline_mode("companion"), do: "companion"
  def normalize_debugger_timeline_mode("separate"), do: "separate"
  def normalize_debugger_timeline_mode(_), do: "mixed"

  @spec debugger_target(Types.wire_input()) :: String.t()
  def debugger_target("companion"), do: "companion"
  def debugger_target("protocol"), do: "companion"
  def debugger_target("phone"), do: "companion"
  def debugger_target(:companion), do: "companion"
  def debugger_target(:protocol), do: "companion"
  def debugger_target(:phone), do: "companion"
  def debugger_target(_), do: "watch"

  @spec debugger_target_runtime(String.t(), map() | nil, map() | nil) :: map() | nil
  def debugger_target_runtime("companion", _watch_runtime, companion_runtime),
    do: companion_runtime

  def debugger_target_runtime(_target, watch_runtime, _companion_runtime), do: watch_runtime

  @spec debugger_other_runtime(String.t(), map() | nil, map() | nil) :: map() | nil
  def debugger_other_runtime("companion", watch_runtime, _companion_runtime), do: watch_runtime
  def debugger_other_runtime(_target, _watch_runtime, companion_runtime), do: companion_runtime

  @spec companion_or_phone_runtime(map() | nil, map() | nil) :: map() | nil
  def companion_or_phone_runtime(companion_runtime, phone_runtime) do
    cond do
      app_runtime?(companion_runtime) -> companion_runtime
      app_runtime?(phone_runtime) -> phone_runtime
      is_map(companion_runtime) -> companion_runtime
      true -> phone_runtime
    end
  end

  @spec app_runtime?(map() | nil) :: boolean()
  def app_runtime?(%{} = runtime) do
    model = Map.get(runtime, :model) || Map.get(runtime, "model") || %{}
    runtime_model = Map.get(model, "runtime_model") || Map.get(model, :runtime_model) || %{}

    is_map(RuntimeArtifacts.introspect(runtime)) or
      (is_map(runtime_model) and
         Enum.any?(Map.keys(runtime_model), fn key ->
           to_string(key) not in [
             "protocol_message_count",
             "protocol_inbound_count",
             "protocol_outbound_count",
             "status"
           ]
         end))
  end

  def app_runtime?(_runtime), do: false
  @spec payload_target(map()) :: String.t() | nil
  def payload_target(payload) when is_map(payload) do
    cond do
      is_binary(Map.get(payload, :target)) -> Map.get(payload, :target)
      is_binary(Map.get(payload, "target")) -> Map.get(payload, "target")
      is_binary(Map.get(payload, :to)) -> Map.get(payload, :to)
      is_binary(Map.get(payload, "to")) -> Map.get(payload, "to")
      true -> nil
    end
  end

  def payload_target(_payload), do: nil
  @spec join_preview_sections(String.t(), String.t()) :: String.t()
  def join_preview_sections("", tree_text), do: tree_text
  def join_preview_sections(runtime_text, ""), do: runtime_text

  def join_preview_sections(runtime_text, tree_text) do
    "#{runtime_text}\n#{tree_text}"
  end

  @spec map_string(map(), atom()) :: String.t() | nil
  def map_string(map, key) when is_map(map) and is_atom(key) do
    case map_lookup(map, key) do
      {:ok, value} when is_binary(value) -> value
      _ -> nil
    end
  end

  @spec map_scalar_string(map(), atom()) :: String.t() | nil
  def map_scalar_string(map, key) when is_map(map) and is_atom(key) do
    case map_lookup(map, key) do
      {:ok, nil} -> nil
      {:ok, value} when is_binary(value) -> value
      {:ok, value} when is_boolean(value) -> to_string(value)
      {:ok, value} when is_integer(value) -> Integer.to_string(value)
      {:ok, value} when is_float(value) -> :erlang.float_to_binary(value, [:compact])
      {:ok, value} when is_atom(value) -> Atom.to_string(value)
      _ -> nil
    end
  end

  @spec map_integer(map(), atom()) :: integer() | nil
  def map_integer(map, key) when is_map(map) and is_atom(key) do
    case map_lookup(map, key) do
      {:ok, value} when is_integer(value) -> value
      _ -> nil
    end
  end

  def map_integer(_map, _key), do: nil

  @spec map_lookup(map(), atom()) :: {:ok, Types.runtime_value()} | :error
  def map_lookup(map, key) when is_map(map) and is_atom(key) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(map, key) ->
        {:ok, Map.get(map, key)}

      Map.has_key?(map, string_key) ->
        {:ok, Map.get(map, string_key)}

      true ->
        :error
    end
  end

  def map_lookup(_map, _key), do: :error

  @spec map_map(map(), atom()) :: map()
  def map_map(map, key) when is_map(map) and is_atom(key) do
    case map_lookup(map, key) do
      {:ok, value} when is_map(value) -> value
      _ -> %{}
    end
  end

  @spec map_list(map(), atom()) :: list()
  def map_list(map, key) when is_map(map) and is_atom(key) do
    case map_lookup(map, key) do
      {:ok, value} when is_list(value) -> value
      _ -> []
    end
  end

  @spec payload_message(map()) :: String.t() | nil
  def payload_message(payload) when is_map(payload) do
    mod = Map.get(payload, :module) || Map.get(payload, "module")
    tgt = Map.get(payload, :target) || Map.get(payload, "target")

    cond do
      is_binary(mod) and is_binary(tgt) ->
        vr = Map.get(payload, :view_root) || Map.get(payload, "view_root")
        mk = Map.get(payload, :main_kind) || Map.get(payload, "main_kind")
        ic = Map.get(payload, :init_cmd_count) || Map.get(payload, "init_cmd_count")
        uc = Map.get(payload, :update_cmd_count) || Map.get(payload, "update_cmd_count")
        ucs = Map.get(payload, :update_case_subject) || Map.get(payload, "update_case_subject")
        ub = Map.get(payload, :update_branch_count) || Map.get(payload, "update_branch_count")
        vcs = Map.get(payload, :view_case_subject) || Map.get(payload, "view_case_subject")
        vb = Map.get(payload, :view_branch_count) || Map.get(payload, "view_branch_count")

        ibc =
          Map.get(payload, :init_case_branch_count) || Map.get(payload, "init_case_branch_count")

        ics = Map.get(payload, :init_case_subject) || Map.get(payload, "init_case_subject")

        sbc =
          Map.get(payload, :subscriptions_case_branch_count) ||
            Map.get(payload, "subscriptions_case_branch_count")

        scs =
          Map.get(payload, :subscriptions_case_subject) ||
            Map.get(payload, "subscriptions_case_subject")

        pc = Map.get(payload, :port_count) || Map.get(payload, "port_count")
        icx = Map.get(payload, :import_count) || Map.get(payload, "import_count")

        iec =
          Map.get(payload, :import_entry_count) || Map.get(payload, "import_entry_count")

        base =
          if is_binary(vr), do: "#{mod} · #{tgt} · #{vr}", else: "#{mod} · #{tgt}"

        base =
          if is_binary(mk) and mk != "" and mk != "unknown" do
            base <> " · main " <> mk
          else
            base
          end

        base =
          if is_integer(ub) and ub > 0 and is_binary(ucs) and ucs != "" do
            base <> " · case " <> ucs
          else
            base
          end

        base =
          if is_integer(vb) and vb > 0 and is_binary(vcs) and vcs != "" do
            base <> " · view case " <> vcs
          else
            base
          end

        base =
          if is_integer(ibc) and ibc > 0 and is_binary(ics) and ics != "" do
            base <> " · init case " <> ics
          else
            base
          end

        base =
          if is_integer(sbc) and sbc > 0 and is_binary(scs) and scs != "" do
            base <> " · subs case " <> scs
          else
            base
          end

        me = Map.get(payload, :module_exposing) || Map.get(payload, "module_exposing")

        base =
          case me do
            ".." ->
              base <> " · exposing (..)"

            xs when is_list(xs) and xs != [] ->
              base <> " · exposing (#{length(xs)})"

            _ ->
              base
          end

        base =
          if is_integer(pc) and pc > 0 do
            base <> " · #{pc} ports"
          else
            base
          end

        base =
          if is_integer(icx) and icx > 0 do
            base <> " · #{icx} imports"
          else
            base
          end

        base =
          if is_integer(iec) and iec > 0 do
            base <> " · #{iec} import lines"
          else
            base
          end

        tac = Map.get(payload, :type_alias_count) || Map.get(payload, "type_alias_count")
        unc = Map.get(payload, :union_type_count) || Map.get(payload, "union_type_count")

        fnc =
          Map.get(payload, :top_level_function_count) ||
            Map.get(payload, "top_level_function_count")

        base =
          if is_integer(tac) and tac > 0 do
            base <> " · #{tac} aliases"
          else
            base
          end

        base =
          if is_integer(unc) and unc > 0 do
            base <> " · #{unc} unions"
          else
            base
          end

        base =
          if is_integer(fnc) and fnc > 0 do
            base <> " · #{fnc} functions"
          else
            base
          end

        pm = Map.get(payload, :port_module)
        pm = if is_boolean(pm), do: pm, else: Map.get(payload, "port_module") == true

        base =
          if pm do
            base <> " · port module"
          else
            base
          end

        base =
          if is_integer(uc) and uc > 0 do
            base <> " · #{uc} update cmds"
          else
            base
          end

        if is_integer(ic) and ic > 0 do
          base <> " · #{ic} init cmds"
        else
          base
        end

      is_binary(Map.get(payload, :message)) ->
        Map.get(payload, :message)

      is_binary(Map.get(payload, "message")) ->
        Map.get(payload, "message")

      is_binary(Map.get(payload, :reason)) ->
        Map.get(payload, :reason)

      is_binary(Map.get(payload, "reason")) ->
        Map.get(payload, "reason")

      is_binary(Map.get(payload, :root)) ->
        Map.get(payload, :root)

      is_binary(Map.get(payload, "root")) ->
        Map.get(payload, "root")

      true ->
        nil
    end
  end

  @spec timeline_kind_for_type(String.t()) :: Types.timeline_kind()
  def timeline_kind_for_type(type) when is_binary(type) do
    cond do
      String.starts_with?(type, "debugger.protocol_") ->
        :protocol

      String.starts_with?(type, "debugger.update_") ->
        :update

      String.starts_with?(type, "debugger.view_") ->
        :render

      type in [
        "debugger.start",
        "debugger.reset",
        "debugger.reload",
        "debugger.contract",
        "debugger.elm_introspect",
        "debugger.elmc_check",
        "debugger.elmc_compile",
        "debugger.elmc_manifest"
      ] ->
        :lifecycle

      true ->
        :other
    end
  end

  def timeline_kind_for_type(_type), do: :other
end
