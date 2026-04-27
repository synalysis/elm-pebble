defmodule ElmEx.IR.Validation do
  @moduledoc """
  Pre-codegen validation of the IR.
  Catches missing declarations, unsupported ops, and arity mismatches
  before backend emission to avoid generating broken C.
  """

  alias ElmEx.IR

  @type diagnostic :: %{
          severity: :error | :warning,
          code: atom(),
          module: String.t(),
          function: String.t() | nil,
          message: String.t()
        }

  @typep expr() :: map()

  @doc """
  Runs all validation passes on the IR and returns a list of diagnostics.
  """
  @spec validate(IR.t()) :: [diagnostic()]
  def validate(%IR{} = ir) do
    check_no_unsupported_ops(ir) ++
      check_no_missing_declarations(ir) ++
      check_function_arity_sanity(ir) ++
      check_no_residual_unsupported_in_expressions(ir)
  end

  @doc """
  Returns true if the IR has no error-level diagnostics.
  """
  @spec valid?(IR.t()) :: boolean()
  def valid?(%IR{} = ir) do
    ir
    |> validate()
    |> Enum.all?(fn d -> d.severity != :error end)
  end

  # Check that no :unsupported ops survive in any expression tree
  @spec check_no_unsupported_ops(ElmEx.IR.t()) :: [diagnostic()]
  defp check_no_unsupported_ops(%IR{} = ir) do
    ir.modules
    |> Enum.flat_map(fn mod ->
      mod.declarations
      |> Enum.filter(&(&1.kind == :function and is_map(&1.expr)))
      |> Enum.flat_map(fn decl ->
        collect_ops(decl.expr, :unsupported)
        |> Enum.map(fn _op ->
          %{
            severity: :warning,
            code: :unsupported_op,
            module: mod.name,
            function: decl.name,
            message: "Function #{mod.name}.#{decl.name} contains an :unsupported op node"
          }
        end)
      end)
    end)
  end

  # Check that all function declarations with bodies have no nil exprs
  # (except type_alias and union declarations)
  @spec check_no_missing_declarations(ElmEx.IR.t()) :: [diagnostic()]
  defp check_no_missing_declarations(%IR{} = ir) do
    all_function_names =
      ir.modules
      |> Enum.flat_map(fn mod ->
        mod.declarations
        |> Enum.filter(&(&1.kind == :function))
        |> Enum.map(fn decl -> "#{mod.name}.#{decl.name}" end)
      end)
      |> MapSet.new()

    # Check that all called functions exist in the IR
    called_functions =
      ir.modules
      |> Enum.flat_map(fn mod ->
        mod.declarations
        |> Enum.filter(&(&1.kind == :function and is_map(&1.expr)))
        |> Enum.flat_map(fn decl ->
          collect_function_calls(decl.expr, mod.name)
        end)
      end)
      |> Enum.uniq()

    called_functions
    |> Enum.reject(&MapSet.member?(all_function_names, &1))
    |> Enum.reject(&is_stdlib_function/1)
    |> Enum.reject(&is_intrinsic_function_reference/1)
    |> Enum.map(fn fqn ->
      %{
        severity: :warning,
        code: :missing_declaration,
        module: String.split(fqn, ".") |> Enum.slice(0..-2//1) |> Enum.join("."),
        function: String.split(fqn, ".") |> List.last(),
        message: "Reference to #{fqn} but no declaration found in IR"
      }
    end)
  end

  # Check basic arity sanity: functions with args should have matching declarations
  @spec check_function_arity_sanity(ElmEx.IR.t()) :: [diagnostic()]
  defp check_function_arity_sanity(%IR{} = ir) do
    ir.modules
    |> Enum.flat_map(fn mod ->
      mod.declarations
      |> Enum.filter(&(&1.kind == :function))
      |> Enum.flat_map(fn decl ->
        args = decl.args || []

        cond do
          decl.expr == nil and length(args) > 0 ->
            [
              %{
                severity: :warning,
                code: :missing_body,
                module: mod.name,
                function: decl.name,
                message: "#{mod.name}.#{decl.name} has #{length(args)} args but no body"
              }
            ]

          true ->
            []
        end
      end)
    end)
  end

  # Deep check for :unsupported inside expressions
  @spec check_no_residual_unsupported_in_expressions(ElmEx.IR.t()) :: [diagnostic()]
  defp check_no_residual_unsupported_in_expressions(%IR{} = ir) do
    ir.modules
    |> Enum.flat_map(fn mod ->
      mod.declarations
      |> Enum.filter(&(&1.kind == :function and is_map(&1.expr)))
      |> Enum.flat_map(fn decl ->
        unsupported_count = count_ops(decl.expr, :unsupported)

        if unsupported_count > 0 do
          [
            %{
              severity: :warning,
              code: :residual_unsupported,
              module: mod.name,
              function: decl.name,
              message:
                "#{mod.name}.#{decl.name} has #{unsupported_count} residual :unsupported nodes"
            }
          ]
        else
          []
        end
      end)
    end)
  end

  # Helper: collect all nodes matching a given op
  @spec collect_ops(expr(), atom()) :: [expr()]
  defp collect_ops(%{op: target_op} = expr, target_op) do
    [expr | collect_ops_children(expr, target_op)]
  end

  defp collect_ops(expr, target_op) when is_map(expr) do
    collect_ops_children(expr, target_op)
  end

  defp collect_ops(_, _), do: []

  @spec collect_ops_children(expr(), atom()) :: [expr()]
  defp collect_ops_children(expr, target_op) when is_map(expr) do
    expr
    |> Map.values()
    |> Enum.flat_map(fn
      child when is_map(child) ->
        collect_ops(child, target_op)

      children when is_list(children) ->
        Enum.flat_map(children, fn
          child when is_map(child) -> collect_ops(child, target_op)
          _ -> []
        end)

      _ ->
        []
    end)
  end

  @spec count_ops(expr(), atom()) :: non_neg_integer()
  defp count_ops(expr, target_op) do
    length(collect_ops(expr, target_op))
  end

  # Collect qualified function call targets
  @spec collect_function_calls(expr(), String.t()) :: [String.t()]
  defp collect_function_calls(%{op: :qualified_call, target: target, args: args}, module)
       when is_binary(target) do
    nested = Enum.flat_map(args || [], &collect_function_calls(&1, module))
    [target | nested]
  end

  defp collect_function_calls(%{op: :call, name: name, args: args}, module)
       when is_binary(name) do
    nested = Enum.flat_map(args || [], &collect_function_calls(&1, module))

    target =
      if String.contains?(name, ".") do
        name
      else
        "#{module}.#{name}"
      end

    [target | nested]
  end

  defp collect_function_calls(expr, module) when is_map(expr) do
    expr
    |> Map.values()
    |> Enum.flat_map(fn
      child when is_map(child) ->
        collect_function_calls(child, module)

      children when is_list(children) ->
        Enum.flat_map(children, fn
          child when is_map(child) -> collect_function_calls(child, module)
          _ -> []
        end)

      _ ->
        []
    end)
  end

  defp collect_function_calls(_, _), do: []

  # Standard library modules whose functions are handled by codegen intrinsics
  @stdlib_modules ~w(
    Basics List Maybe Result String Char Tuple Dict Set Array
    Debug Bitwise Task Process Platform Cmd Sub
    Json.Decode Json.Encode
    Pebble.Cmd Pebble.Events Pebble.Platform Pebble.Ui PebbleCmd PebbleEvents PebbleUi PebblePlatform
  )

  @intrinsic_functions MapSet.new([
                         "__add__",
                         "__sub__",
                         "__mul__",
                         "__fdiv__",
                         "__idiv__"
                       ])

  @spec is_stdlib_function(String.t()) :: boolean()
  defp is_stdlib_function(fqn) when is_binary(fqn) do
    parts = String.split(fqn, ".")
    module = parts |> Enum.slice(0..-2//1) |> Enum.join(".")
    module in @stdlib_modules
  end

  @spec is_intrinsic_function_reference(String.t()) :: boolean()
  defp is_intrinsic_function_reference(fqn) when is_binary(fqn) do
    fqn
    |> String.split(".")
    |> List.last()
    |> then(&MapSet.member?(@intrinsic_functions, &1))
  end
end
