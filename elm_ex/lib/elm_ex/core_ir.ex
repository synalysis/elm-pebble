defmodule ElmEx.CoreIR do
  @moduledoc """
  Backend-stable normalized IR contract used by non-C backends (e.g. elm_executor).
  """

  alias ElmEx.IR
  alias ElmEx.IR.Validation
  alias ElmEx.CoreIR.Types
  alias ElmEx.CoreIR.Validate

  @type t :: Types.t()

  @enforce_keys [:version, :modules, :diagnostics, :deterministic_sha256]
  defstruct [:version, :modules, :diagnostics, :deterministic_sha256]

  @doc """
  Validates structural shape of normalized Core IR (modules, declarations, expr ops).
  """
  @spec validate_shape(Types.wire_core_ir()) :: {:ok, t()} | {:error, [Validate.shape_error()]}
  defdelegate validate_shape(core_ir), to: Validate

  @spec from_ir(IR.t(), keyword()) :: {:ok, t()} | {:error, map()}
  def from_ir(%IR{} = ir, opts \\ []) do
    strict? = Keyword.get(opts, :strict?, false)

    diagnostics =
      Validation.validate(ir)
      |> Enum.map(&normalize_diagnostic/1)

    modules =
      ir.modules
      |> Enum.map(&normalize_module/1)
      |> Enum.sort_by(& &1["name"])

    core_ir = %__MODULE__{
      version: "elm_ex.core_ir.v1",
      modules: modules,
      diagnostics: diagnostics,
      deterministic_sha256: stable_term_sha256(modules)
    }

    cond do
      strict? and has_blocking_diagnostics?(diagnostics) ->
        {:error,
         %{
           type: "core_ir_validation_failed",
           message: "CoreIR contains unsupported semantics for strict backend compilation.",
           diagnostics: diagnostics
         }}

      strict? ->
        case validate_shape(core_ir) do
          {:ok, validated} ->
            {:ok, validated}

          {:error, shape_errors} ->
            {:error,
             %{
               type: "core_ir_validation_failed",
               message: "CoreIR failed structural shape validation.",
               diagnostics: diagnostics,
               shape_errors: shape_errors
             }}
        end

      true ->
        {:ok, core_ir}
    end
  end

  @spec normalize_module(ElmEx.IR.Module.t()) :: map()
  defp normalize_module(module) do
    %{
      "name" => module.name,
      "imports" => module.imports |> Enum.sort(),
      "unions" => normalize_unions(module.unions),
      "declarations" => module.declarations |> Enum.map(&normalize_declaration/1)
    }
  end

  @spec normalize_unions(map() | list() | atom() | nil) :: map()
  defp normalize_unions(unions) when is_map(unions) do
    unions
    |> Enum.map(fn {name, constructors} ->
      {to_string(name), normalize_constructors(constructors)}
    end)
    |> Enum.sort_by(fn {name, _} -> name end)
    |> Map.new()
  end

  defp normalize_unions(_), do: %{}

  @spec normalize_constructors(map() | list() | atom() | String.t() | number() | boolean() | nil) ::
          Types.normalized_value()
  defp normalize_constructors(constructors) when is_map(constructors) do
    constructors
    |> Enum.map(fn {ctor, payload} ->
      {to_string(ctor), normalize_value(payload)}
    end)
    |> Enum.sort_by(fn {name, _} -> name end)
    |> Map.new()
  end

  defp normalize_constructors(other), do: normalize_value(other)

  @spec normalize_declaration(ElmEx.IR.Declaration.t()) :: map()
  defp normalize_declaration(decl) do
    %{
      "kind" => to_string(decl.kind),
      "name" => decl.name,
      "type" => decl.type,
      "args" => decl.args || [],
      "ownership" => Enum.map(decl.ownership || [], &to_string/1),
      "expr" => normalize_expr(decl.expr)
    }
  end

  @spec normalize_expr(map() | nil) :: Types.expr() | Types.normalized_value() | nil
  defp normalize_expr(nil), do: nil

  defp normalize_expr(expr) when is_map(expr) do
    expr
    |> Enum.map(fn {k, v} ->
      key = to_string(k)
      {key, if(key == "op", do: normalize_op_value(v), else: normalize_value(v))}
    end)
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Map.new()
  end

  @spec normalize_op_value(atom() | String.t() | number()) :: String.t()
  defp normalize_op_value(v) when is_atom(v), do: to_string(v)
  defp normalize_op_value(v) when is_binary(v), do: v
  defp normalize_op_value(v), do: to_string(v)

  @spec normalize_value(Types.normalized_value()) :: Types.normalized_value()
  defp normalize_value(value) when is_map(value), do: normalize_expr(value)
  defp normalize_value(value) when is_list(value), do: Enum.map(value, &normalize_value/1)
  defp normalize_value(value), do: value

  @spec normalize_diagnostic(map()) :: map()
  defp normalize_diagnostic(diagnostic) when is_map(diagnostic) do
    %{
      "severity" => to_string(Map.get(diagnostic, :severity, :warning)),
      "code" => to_string(Map.get(diagnostic, :code, :unknown)),
      "module" => Map.get(diagnostic, :module),
      "function" => Map.get(diagnostic, :function),
      "message" => Map.get(diagnostic, :message, "")
    }
  end

  @spec has_blocking_diagnostics?([Types.normalized_diagnostic()]) :: boolean()
  defp has_blocking_diagnostics?(diagnostics) do
    Enum.any?(diagnostics, fn d ->
      d["severity"] == "error" or d["code"] in ["unsupported_op", "residual_unsupported"]
    end)
  end

  @spec stable_term_sha256(Types.normalized_value() | [Types.normalized_module()]) :: String.t()
  defp stable_term_sha256(term) do
    :crypto.hash(:sha256, :erlang.term_to_binary(term))
    |> Base.encode16(case: :lower)
  end
end
