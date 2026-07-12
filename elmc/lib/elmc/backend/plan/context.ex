defmodule Elmc.Backend.Plan.Context do
  @moduledoc """
  Compile-time context for plan lowering: tail vs scratch destinations.

  Replaces scattered C-codegen env keys (`__function_tail_compile__`,
  `__branch_out__`, `__allow_fn_out_slot__`) with an explicit stack.
  """

  alias Elmc.Backend.Plan.Types

  defstruct [
    :dest_stack,
    :function_tail,
    :rc_required,
    :fallible,
    :module,
    :function_name,
    :decl_map,
    :locals,
    :local_types,
    :params,
    :letrec_refs,
    :letrec_self,
    :letrec_in_closure
  ]

  @type t :: %__MODULE__{
          dest_stack: [dest()],
          function_tail: boolean(),
          rc_required: boolean(),
          fallible: boolean(),
          module: String.t() | nil,
          function_name: String.t() | nil,
          decl_map: map(),
          locals: %{String.t() => Types.reg()},
          local_types: %{String.t() => String.t()},
          params: [String.t()],
          letrec_refs: %{String.t() => String.t()},
          letrec_self: String.t() | nil,
          letrec_in_closure: boolean()
        }

  @type dest :: :scratch | :fn_out | :branch_out

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    function_tail? = Keyword.get(opts, :function_tail, false)

    %__MODULE__{
      dest_stack: if(function_tail?, do: [:fn_out], else: [:scratch]),
      function_tail: function_tail?,
      rc_required: Keyword.get(opts, :rc_required, false),
      fallible: Keyword.get(opts, :fallible, false),
      module: Keyword.get(opts, :module),
      function_name: Keyword.get(opts, :function_name),
      decl_map: Keyword.get(opts, :decl_map, %{}),
      locals: Keyword.get(opts, :locals, %{}),
      local_types: Keyword.get(opts, :local_types, %{}),
      params: Keyword.get(opts, :params, []),
      letrec_refs: Keyword.get(opts, :letrec_refs, %{}),
      letrec_self: Keyword.get(opts, :letrec_self),
      letrec_in_closure: Keyword.get(opts, :letrec_in_closure, false)
    }
  end

  @spec from_compile_env(map()) :: t()
  def from_compile_env(env) when is_map(env) do
    function_tail =
      Map.get(env, :__function_tail_compile__, false) or
        Map.get(env, :__allow_fn_out_slot__, false)

    %__MODULE__{
      dest_stack: dest_stack_from_env(env, function_tail),
      function_tail: function_tail,
      rc_required: Map.get(env, :__rc_required__, false),
      fallible: Map.get(env, :__rc_catch__, false),
      module: Map.get(env, :__module__),
      function_name: Map.get(env, :__function_name__),
      decl_map: Map.get(env, :__program_decls__, %{}),
      locals: locals_from_env(env),
      local_types: %{},
      params: params_from_env(env)
    }
  end

  defp params_from_env(env) do
    case Map.get(env, :__function_args__) do
      args when is_list(args) -> args
      _ -> []
    end
  end

  defp dest_stack_from_env(env, function_tail?) do
    cond do
      function_tail? -> [:fn_out]
      branch_out = Map.get(env, :__branch_out__) ->
        if is_binary(branch_out), do: [:branch_out], else: [:scratch]

      true ->
        [:scratch]
    end
  end

  defp locals_from_env(env) do
    env
    |> Enum.filter(fn
      {k, v} when is_binary(k) and is_integer(v) -> true
      _ -> false
    end)
    |> Map.new()
  end

  @spec push_tail(t()) :: t()
  def push_tail(ctx), do: %{ctx | dest_stack: [:fn_out | ctx.dest_stack], function_tail: true}

  @spec push_branch(t()) :: t()
  def push_branch(ctx), do: %{ctx | dest_stack: [:branch_out | ctx.dest_stack]}

  # Control-flow arms (if/case) must not target fn_out; merge/phi publishes the tail result.
  @spec for_branch_arm(t()) :: t()
  def for_branch_arm(ctx), do: %{ctx | dest_stack: [:scratch], function_tail: false}

  @spec pop_dest(t()) :: t()
  def pop_dest(%{dest_stack: [_ | rest]} = ctx), do: %{ctx | dest_stack: rest}
  def pop_dest(ctx), do: ctx

  @spec dest_for_call(t()) :: dest()
  def dest_for_call(ctx) do
    case ctx.dest_stack do
      [dest | _] -> dest
      [] -> :scratch
    end
  end

  @spec dest_reg(t(), Types.reg()) :: Types.result_slot() | Types.reg()
  def dest_reg(ctx, scratch_reg) do
    case dest_for_call(ctx) do
      :fn_out -> :fn_out
      :branch_out -> :branch_out
      :scratch -> scratch_reg
    end
  end

  @spec function_tail?(t()) :: boolean()
  def function_tail?(ctx), do: ctx.function_tail or dest_for_call(ctx) == :fn_out

  @spec put_local(t(), String.t(), Types.reg()) :: t()
  def put_local(ctx, name, reg) when is_binary(name) do
    %{ctx | locals: Map.put(ctx.locals, name, reg)}
  end

  @spec local_reg(t(), String.t()) :: Types.reg() | nil
  def local_reg(ctx, name) when is_binary(name), do: Map.get(ctx.locals, name)

  @spec put_local_type(t(), String.t(), String.t()) :: t()
  def put_local_type(ctx, name, type) when is_binary(name) and is_binary(type) do
    %{ctx | local_types: Map.put(ctx.local_types || %{}, name, type)}
  end

  @spec local_type(t(), String.t()) :: String.t() | nil
  def local_type(ctx, name) when is_binary(name), do: Map.get(ctx.local_types || %{}, name)

  @spec fresh_locals(t()) :: t()
  def fresh_locals(ctx), do: %{ctx | locals: %{}, local_types: %{}}

  @spec put_letrec_ref(t(), String.t(), String.t()) :: t()
  def put_letrec_ref(ctx, name, ref) when is_binary(name) and is_binary(ref) do
    %{ctx | letrec_refs: Map.put(ctx.letrec_refs || %{}, name, ref)}
  end

  @spec letrec_ref(t(), String.t()) :: String.t() | nil
  def letrec_ref(ctx, name) when is_binary(name), do: Map.get(ctx.letrec_refs || %{}, name)
end
