defmodule Elmc.Backend.CCodegen.FunctionEmit do
  @moduledoc false

  alias Elmc.Backend.CCodegen.DebugProbes
  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Expr
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.LetAnalysis
  alias Elmc.Backend.CCodegen.Native.FunctionCall, as: NativeFunctionCall
  alias Elmc.Backend.CCodegen.TypeParsing
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util

  @c_reserved_binding_names ~w(args argc out_cmds max_cmds skip count emitted)

  @spec emit_function_def(
          Types.function_declaration(),
          String.t(),
          String.t(),
          %{optional({String.t(), String.t()}) => non_neg_integer()},
          Types.function_decl_map(),
          boolean()
        ) :: String.t()
  def emit_function_def(
        decl,
        module_name,
        c_name,
        function_arities,
        decl_map,
        emit_wrapper?
      ) do
    if NativeFunctionCall.native_args?(decl, module_name, decl_map) do
      emit_native_function_def(
        decl,
        module_name,
        c_name,
        function_arities,
        decl_map,
        emit_wrapper?
      )
    else
      """
      ElmcValue *#{c_name}(ElmcValue ** const args, const int argc) {
        /* Ownership policy: #{Enum.join(decl.ownership, ", ")} */
        #{emit_body(decl, module_name, function_arities, decl_map)}
      }
      """
    end
  end

  @spec emit_body(
          Types.function_declaration(),
          String.t(),
          %{optional({String.t(), String.t()}) => non_neg_integer()},
          Types.function_decl_map()
        ) :: String.t()
  def emit_body(decl, module_name, function_arities \\ %{}, decl_map \\ %{})

  def emit_body(%{expr: nil}, _module_name, _function_arities, _decl_map) do
    "(void)args; (void)argc; return elmc_int_zero();"
  end

  def emit_body(decl, module_name, function_arities, decl_map) do
    arg_names = decl.args || []
    arg_bindings = c_arg_bindings(arg_names)
    {entry_probe, exit_probe} = DebugProbes.entry_exit_probes(module_name, decl.name)

    arg_binding_code =
      arg_bindings
      |> Enum.map(fn {_arg, c_arg, index} ->
        "ElmcValue *#{c_arg} = (argc > #{index}) ? args[#{index}] : NULL;"
      end)
      |> Enum.join("\n  ")

    unused_casts =
      arg_bindings
      |> Enum.map(fn {_arg, c_arg, _index} -> c_arg end)
      |> Enum.map_join("\n  ", fn name -> "(void)#{name};" end)

    env =
      arg_bindings
      |> Enum.reduce(%{__module__: module_name}, fn arg, acc ->
        {source_arg, c_arg, _index} = arg
        Map.put(acc, source_arg, c_arg)
      end)
      |> Map.put(:__function_name__, decl.name)
      |> put_typed_arg_bindings(arg_bindings, decl.type)
      |> Map.put(:__function_arities__, function_arities)
      |> Map.put(:__program_decls__, decl_map)
      |> Map.put(
        :__function_analysis__,
        LetAnalysis.analyze_function_expr(
          decl.expr || %{op: :int_literal, value: 0},
          module_name,
          decl_map
        )
      )

    {code, result_var, _counter} =
      Host.compile_expr(decl.expr || %{op: :int_literal, value: 0}, env, 0)

    result_probe = DebugProbes.result_probe(module_name, decl.name, result_var)

    """
    (void)args;
      (void)argc;
    #{arg_binding_code}
      #{unused_casts}
      #{entry_probe}
      #{code}
      #{exit_probe}
      #{result_probe}
      return #{result_var};
    """
  end

  @spec generic_native_function_prototypes(
          ElmEx.IR.t(),
          MapSet.t(Types.function_decl_key()),
          Types.function_decl_map()
        ) :: String.t()
  def generic_native_function_prototypes(ir, generic_targets, decl_map) do
    ir.modules
    |> Enum.flat_map(fn mod ->
      mod.declarations
      |> Enum.filter(
        &(&1.kind == :function and MapSet.member?(generic_targets, {mod.name, &1.name}) and
            NativeFunctionCall.native_args?(&1, mod.name, decl_map))
      )
      |> Enum.map(fn decl ->
        c_name = Util.module_fn_name(mod.name, decl.name)
        "static ElmcValue *#{c_name}_native(#{NativeFunctionCall.params(decl, mod.name, decl_map)});"
      end)
    end)
    |> Enum.join("\n")
  end

  @spec c_arg_bindings([String.t()]) :: [Types.c_arg_binding()]
  def c_arg_bindings(arg_names) do
    arg_names
    |> Enum.with_index()
    |> Enum.map(fn {arg, index} ->
      c_arg =
        cond do
          c_reserved_binding_name?(arg) -> "#{arg}_arg"
          Enum.count(arg_names, &(&1 == arg)) > 1 -> "#{arg}_#{index}"
          true -> arg
        end

      {arg, c_arg, index}
    end)
  end

  @spec put_typed_arg_bindings(Types.compile_env(), [Types.c_arg_binding()], String.t() | nil) ::
          Types.compile_env()
  def put_typed_arg_bindings(env, arg_bindings, type) when is_binary(type) do
    arg_types = TypeParsing.function_arg_types(type)

    arg_bindings
    |> Enum.zip(arg_types)
    |> Enum.reduce(env, fn {{arg, _c_arg, _index}, arg_type}, acc ->
      normalized_type = TypeParsing.normalize_type_name(arg_type)

      acc =
        case normalized_type do
          "Int" -> EnvBindings.put_boxed_int_binding(acc, arg, true)
          "Bool" -> EnvBindings.put_boxed_bool_binding(acc, arg, true)
          _other ->
            if TypeParsing.enum_type?(arg_type),
              do: EnvBindings.put_boxed_int_binding(acc, arg, true),
              else: acc
        end

      acc
      |> EnvBindings.put_record_shape(arg, Expr.record_shape_for_type(arg_type, acc))
      |> put_var_type(arg, normalized_type)
    end)
  end

  def put_typed_arg_bindings(env, _arg_bindings, _type), do: env

  @spec c_reserved_binding_name?(String.t()) :: boolean()
  defp c_reserved_binding_name?(name), do: name in @c_reserved_binding_names

  defp put_var_type(env, name, type), do: EnvBindings.put_var_type(env, name, type)

  @spec emit_native_function_def(
          Types.function_declaration(),
          String.t(),
          String.t(),
          %{optional({String.t(), String.t()}) => non_neg_integer()},
          Types.function_decl_map(),
          boolean()
        ) :: String.t()
  defp emit_native_function_def(
         decl,
         module_name,
         c_name,
         function_arities,
         decl_map,
         emit_wrapper?
       ) do
    arg_names = decl.args || []
    c_arg_bindings = c_arg_bindings(arg_names)
    arg_kinds = NativeFunctionCall.arg_kinds(decl, module_name, decl_map)
    {entry_probe, exit_probe} = DebugProbes.entry_exit_probes(module_name, decl.name)

    wrapper_bindings =
      c_arg_bindings
      |> Enum.zip(arg_kinds)
      |> Enum.map_join("\n  ", fn {{_arg, c_arg, index}, kind} ->
        case kind do
          :native_int ->
            "elmc_int_t #{c_arg} = (argc > #{index} && args[#{index}]) ? elmc_as_int(args[#{index}]) : 0;"

          :native_bool ->
            "elmc_int_t #{c_arg} = (argc > #{index} && args[#{index}]) ? elmc_as_bool(args[#{index}]) : 0;"

          :boxed ->
            "ElmcValue *#{c_arg} = (argc > #{index}) ? args[#{index}] : NULL;"
        end
      end)

    native_args =
      c_arg_bindings
      |> Enum.map(fn {_arg, c_arg, _index} -> c_arg end)
      |> Enum.join(", ")

    native_env =
      c_arg_bindings
      |> Enum.zip(arg_kinds)
      |> Enum.reduce(%{__module__: module_name}, fn {{source_arg, c_arg, _index}, kind}, acc ->
        case kind do
          :native_int -> EnvBindings.put_native_int_binding(acc, source_arg, c_arg)
          :native_bool -> EnvBindings.put_native_bool_binding(acc, source_arg, c_arg)
          :boxed -> Map.put(acc, source_arg, c_arg)
        end
      end)
      |> put_typed_arg_bindings(c_arg_bindings, decl.type)
      |> Map.put(:__function_name__, decl.name)
      |> Map.put(:__function_arities__, function_arities)
      |> Map.put(:__program_decls__, decl_map)
      |> Map.put(
        :__function_analysis__,
        LetAnalysis.analyze_function_expr(
          decl.expr || %{op: :int_literal, value: 0},
          module_name,
          decl_map
        )
      )

    unused_casts =
      c_arg_bindings
      |> Enum.map(fn {_arg, c_arg, _index} -> c_arg end)
      |> Enum.map_join("\n  ", fn name -> "(void)#{name};" end)

    {body_code, body_var, _counter} =
      Host.compile_expr(decl.expr || %{op: :int_literal, value: 0}, native_env, 0)

    wrapper_def =
      if emit_wrapper? do
        """
        ElmcValue *#{c_name}(ElmcValue ** const args, const int argc) {
          /* Ownership policy: #{Enum.join(decl.ownership, ", ")} */
          (void)args;
          (void)argc;
          #{wrapper_bindings}
          return #{c_name}_native(#{native_args});
        }
        """
      else
        ""
      end

    """
    #{wrapper_def}
    static ElmcValue *#{c_name}_native(#{NativeFunctionCall.params(decl, module_name, decl_map)}) {
      #{unused_casts}
      #{entry_probe}
      #{body_code}
      #{exit_probe}
      return #{body_var};
    }
    """
  end
end
