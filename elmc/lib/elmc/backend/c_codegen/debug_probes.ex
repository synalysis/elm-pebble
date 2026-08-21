defmodule Elmc.Backend.CCodegen.DebugProbes do
  @moduledoc false
  # Call-site agent probes stay disabled. Non-prod builds still emit the
  # `elmc_agent_generated_probe` helper via `Emit.pebble_debug_probe_prelude/1`.

  alias Elmc.Backend.CCodegen.Types, as: Types

  @type probe_pair :: {String.t(), String.t()}
  @type probe_position ::
          :before | :after | :before_args | :after_args | :after_call | atom()

  @spec entry_exit_probes(String.t(), String.t()) :: probe_pair()
  def entry_exit_probes(_module_name, _name), do: {"", ""}

  @spec result_probe(String.t(), String.t(), String.t()) :: String.t()
  def result_probe(_module_name, _name, _result_var), do: ""

  @spec list_literal_probe(Types.compile_env(), String.t(), Types.compile_counter()) :: String.t()
  def list_literal_probe(_env, _result_var, _counter), do: ""

  @spec append_probe(
          Types.compile_env(),
          String.t(),
          String.t(),
          Types.compile_counter()
        ) :: String.t()
  def append_probe(_env, _function, _result_var, _counter), do: ""

  @spec let_probe(Types.compile_env(), Types.binding_name(), probe_position()) :: String.t()
  def let_probe(_env, _name, _position), do: ""

  @type probe_subject :: String.t() | nil

  @spec field_probe(Types.compile_env(), probe_subject(), String.t(), probe_position()) :: String.t()
  def field_probe(_env, _arg, _field, _position), do: ""

  @spec call_probe(Types.compile_env(), String.t(), String.t(), probe_position()) :: String.t()
  def call_probe(_env, _module_name, _name, _position), do: ""

  @spec region(String.t()) :: String.t()
  def region(_probe), do: ""
end
