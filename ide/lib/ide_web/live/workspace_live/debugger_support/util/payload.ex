defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Util.Payload do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types

  @type wire_payload :: Types.wire_payload()
  @type elm_introspect :: Types.elm_introspect()
  @type payload_message_input :: elm_introspect() | wire_payload()

  @spec field(wire_payload(), atom()) :: String.t() | nil
  def field(payload, key) when is_map(payload) do
    str = Atom.to_string(key)
    v = Map.get(payload, key) || Map.get(payload, str)
    if is_binary(v), do: v
  end

  def field(_payload, _key), do: nil

  @spec target(wire_payload()) :: String.t() | nil
  def target(payload) when is_map(payload) do
    cond do
      is_binary(Map.get(payload, :target)) -> Map.get(payload, :target)
      is_binary(Map.get(payload, "target")) -> Map.get(payload, "target")
      is_binary(Map.get(payload, :to)) -> Map.get(payload, :to)
      is_binary(Map.get(payload, "to")) -> Map.get(payload, "to")
      true -> nil
    end
  end

  def target(_payload), do: nil

  @spec message(payload_message_input()) :: String.t() | nil
  def message(payload) when is_map(payload) do
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
end
