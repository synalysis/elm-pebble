defmodule Elmc.Backend.CCodegen.DebugProbes do
  @moduledoc false

  alias Elmc.Backend.CCodegen.ProdMode
  alias Elmc.Backend.CCodegen.RcRuntimeEmit
  alias Elmc.Backend.CCodegen.Types

  @type probe_pair :: {String.t(), String.t()}
  @type probe_position ::
          :before | :after | :before_args | :after_args | :after_call | atom()

  @spec entry_exit_probes(String.t(), String.t()) :: probe_pair()
  def entry_exit_probes(module_name, name) do
    if ProdMode.enabled?() do
      {"", ""}
    else
      entry_exit_probes_impl(module_name, name)
    end
  end

  defp entry_exit_probes_impl("Main", name) do
    case name do
      "view" -> {region("elmc_agent_generated_probe(0xED998100);"), ""}
      "faceOps" -> {region("elmc_agent_generated_probe(0xED998200);"), ""}
      _ -> {"", ""}
    end
  end

  defp entry_exit_probes_impl("Pebble.Ui", "toUiNode"),
    do: {region("elmc_agent_generated_probe(0xED998300);"), ""}

  defp entry_exit_probes_impl(_module_name, _name), do: {"", ""}

  @spec result_probe(String.t(), String.t(), String.t()) :: String.t()
  def result_probe(module_name, name, result_var) do
    if ProdMode.enabled?(), do: "", else: result_probe_impl(module_name, name, result_var)
  end

  defp result_probe_impl("Main", "view", result_var),
    do: shape_probe(result_var, 0xED998110, 0xED998111, 0xED998112, 0xED998113)

  defp result_probe_impl("Main", "faceOps", result_var),
    do: list_probe(result_var, 0xED998210, 0xED998211, 0xED998212, 0xED998213)

  defp result_probe_impl("Pebble.Ui", "toUiNode", result_var),
    do: shape_probe(result_var, 0xED998310, 0xED998311, 0xED998312, 0xED998313)

  defp result_probe_impl(_module_name, _name, _result_var), do: ""

  @spec list_literal_probe(Types.compile_env(), String.t(), Types.compile_counter()) :: String.t()
  def list_literal_probe(env, result_var, counter) do
    if ProdMode.enabled?() do
      ""
    else
      list_literal_probe_impl(env, result_var, counter)
    end
  end

  defp list_literal_probe_impl(env, result_var, counter) do
    if Map.get(env, :__module__) == "Main" and Map.get(env, :__function_name__) == "faceOps" do
      base = 0xED998500 + Integer.mod(counter, 16) * 0x10
      list_probe(result_var, base, base + 1, base + 2, base + 3)
    else
      ""
    end
  end

  @spec append_probe(
          Types.compile_env(),
          String.t(),
          String.t(),
          Types.compile_counter()
        ) :: String.t()
  def append_probe(env, function, result_var, counter) do
    if ProdMode.enabled?() do
      ""
    else
      append_probe_impl(env, function, result_var, counter)
    end
  end

  defp append_probe_impl(env, "elmc_append", result_var, counter) do
    if Map.get(env, :__module__) == "Main" and Map.get(env, :__function_name__) == "faceOps" do
      base = 0xED998400 + Integer.mod(counter, 16) * 0x10
      list_probe(result_var, base, base + 1, base + 2, base + 3)
    else
      ""
    end
  end

  defp append_probe_impl(_env, _function, _result_var, _counter), do: ""

  @spec let_probe(Types.compile_env(), Types.binding_name(), probe_position()) :: String.t()
  def let_probe(env, _name, _position) do
    if Map.get(env, :__module__) == "Main" and Map.get(env, :__function_name__) == "faceOps" do
      ""
    else
      ""
    end
  end

  @spec field_probe(Types.compile_env(), term(), String.t(), probe_position()) :: String.t()
  def field_probe(_env, _arg, _field, _position), do: ""

  @spec call_probe(Types.compile_env(), String.t(), String.t(), probe_position()) :: String.t()
  def call_probe(_env, _module_name, _name, _position), do: ""

  @spec region(String.t()) :: String.t()
  def region(""), do: ""

  def region(probe) do
    """
    // #region agent log
    #{probe}
    // #endregion
    """
  end

  @spec shape_probe(String.t(), non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          String.t()
  defp shape_probe(result_var, other_tag, tuple_tag, list_tag, null_tag) do
    value = RcRuntimeEmit.value_expr(result_var)

    region("""
    if (!#{value}) {
      elmc_agent_generated_probe(#{hex_tag(null_tag)});
    } else if (#{value}->tag == ELMC_TAG_TUPLE2) {
      elmc_agent_generated_probe(#{hex_tag(tuple_tag)});
    } else if (#{value}->tag == ELMC_TAG_LIST) {
      elmc_agent_generated_probe(#{hex_tag(list_tag)});
    } else {
      elmc_agent_generated_probe(#{hex_tag(other_tag)});
    }
    """)
  end

  @spec list_probe(String.t(), non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          String.t()
  defp list_probe(result_var, empty_tag, nonempty_tag, other_tag, null_tag) do
    value = RcRuntimeEmit.value_expr(result_var)

    region("""
    if (!#{value}) {
      elmc_agent_generated_probe(#{hex_tag(null_tag)});
    } else if (#{value}->tag == ELMC_TAG_LIST && #{value}->payload == NULL) {
      elmc_agent_generated_probe(#{hex_tag(empty_tag)});
    } else if (#{value}->tag == ELMC_TAG_LIST) {
      elmc_agent_generated_probe(#{hex_tag(nonempty_tag)});
    } else {
      elmc_agent_generated_probe(#{hex_tag(other_tag)});
    }
    """)
  end

  @spec hex_tag(non_neg_integer()) :: String.t()
  defp hex_tag(tag), do: "0x" <> (tag |> Integer.to_string(16) |> String.upcase())
end
