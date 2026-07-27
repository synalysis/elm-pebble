defmodule Elmc.Backend.CCodegen.StoragePlan do
  @moduledoc false

  @type primitive :: :int | :float | :char | :bool
  @type elem_schema ::
          {:primitive, primitive()}
          | {:record, String.t(), String.t()}
          | {:boxed, :value}

  @type layout :: :compact | :native_linked | :boxed_cons | :mixed | :unboxed
  @type length_info :: :known | :unknown
  @type access :: :sequential | :random

  @type t :: %__MODULE__{
          elem: elem_schema() | nil,
          layout: layout(),
          length: length_info(),
          access: access()
        }

  defstruct elem: nil,
            layout: :mixed,
            length: :unknown,
            access: :sequential

  @spec mixed() :: t()
  def mixed, do: %__MODULE__{layout: :mixed}

  @spec int_compact(keyword()) :: t()
  def int_compact(opts \\ []) do
    %__MODULE__{
      elem: {:primitive, :int},
      layout: :compact,
      length: Keyword.get(opts, :length, :unknown),
      access: Keyword.get(opts, :access, :sequential)
    }
  end

  @spec int_native_linked() :: t()
  def int_native_linked do
    %__MODULE__{
      elem: {:primitive, :int},
      layout: :native_linked,
      length: :unknown,
      access: :sequential
    }
  end

  @spec float_compact(keyword()) :: t()
  def float_compact(opts \\ []) do
    %__MODULE__{
      elem: {:primitive, :float},
      layout: :compact,
      length: Keyword.get(opts, :length, :unknown),
      access: Keyword.get(opts, :access, :sequential)
    }
  end

  @spec float_native_linked() :: t()
  def float_native_linked do
    %__MODULE__{
      elem: {:primitive, :float},
      layout: :native_linked,
      length: :unknown,
      access: :sequential
    }
  end

  @spec scalar_unboxed(primitive()) :: t()
  def scalar_unboxed(kind) when kind in [:int, :float, :bool, :char] do
    %__MODULE__{
      elem: {:primitive, kind},
      layout: :unboxed,
      length: :known,
      access: :sequential
    }
  end

  @spec unboxed_scalar?(t()) :: boolean()
  def unboxed_scalar?(%__MODULE__{layout: :unboxed, elem: {:primitive, _}}), do: true
  def unboxed_scalar?(_), do: false

  @spec record_compact(String.t(), String.t(), keyword()) :: t()
  def record_compact(mod, name, opts \\ []) when is_binary(mod) and is_binary(name) do
    %__MODULE__{
      elem: {:record, mod, name},
      layout: :compact,
      length: Keyword.get(opts, :length, :unknown),
      access: Keyword.get(opts, :access, :sequential)
    }
  end

  @spec from_legacy_repr(:int_list | :float_list | :record_seq | :mixed) :: t()
  def from_legacy_repr(:int_list), do: int_compact()
  def from_legacy_repr(:float_list), do: float_compact()
  def from_legacy_repr(:record_seq), do: %__MODULE__{layout: :compact, elem: nil, length: :unknown, access: :sequential}
  def from_legacy_repr(:mixed), do: mixed()
  def from_legacy_repr(_), do: mixed()

  @spec from_record_repr(:record_seq | :mixed, {String.t(), String.t()} | nil) :: t()
  def from_record_repr(:record_seq, {mod, name}), do: record_compact(mod, name)
  def from_record_repr(:record_seq, _), do: %__MODULE__{layout: :compact, access: :sequential}

  def from_record_repr(:mixed, {mod, name}) when is_binary(mod) and is_binary(name) do
    %__MODULE__{
      elem: {:record, mod, name},
      layout: :boxed_cons,
      length: :unknown,
      access: :sequential
    }
  end

  def from_record_repr(:mixed, _), do: mixed()
  def from_record_repr(_, _), do: mixed()

  @spec to_legacy_repr(t()) :: :int_list | :float_list | :record_seq | :mixed
  def to_legacy_repr(%__MODULE__{layout: :compact, elem: {:primitive, :int}}), do: :int_list
  def to_legacy_repr(%__MODULE__{layout: :compact, elem: {:primitive, :float}}), do: :float_list
  def to_legacy_repr(%__MODULE__{layout: :compact, elem: {:record, _, _}}), do: :record_seq
  def to_legacy_repr(%__MODULE__{}), do: :mixed

  @spec compact_only?(t()) :: boolean()
  def compact_only?(%__MODULE__{layout: :compact}), do: true
  def compact_only?(_), do: false

  @spec dual_path?(t()) :: boolean()
  def dual_path?(%__MODULE__{layout: :mixed}), do: true
  def dual_path?(_), do: false

  @doc """
  True when a list may use compact int-list storage and needs INT_LIST/cons dual loops.
  Record and generic boxed lists use cons (or record_seq) only.
  """
  @spec int_list_dual_eligible?(t()) :: boolean()
  def int_list_dual_eligible?(%__MODULE__{elem: {:primitive, :int}}), do: true
  def int_list_dual_eligible?(%__MODULE__{elem: {:primitive, :float}}), do: true
  def int_list_dual_eligible?(%__MODULE__{layout: :mixed, elem: nil}), do: true
  def int_list_dual_eligible?(_), do: false

  @spec loop_repr(t()) :: :compact | :native_linked | :cons | :dual | :float_list | :record_seq
  def loop_repr(%__MODULE__{layout: :compact, elem: {:primitive, :int}}), do: :compact
  def loop_repr(%__MODULE__{layout: :compact, elem: {:primitive, :float}}), do: :float_list
  def loop_repr(%__MODULE__{layout: :compact, elem: {:record, _, _}}), do: :record_seq
  def loop_repr(%__MODULE__{layout: :compact}), do: :compact
  def loop_repr(%__MODULE__{layout: :native_linked}), do: :native_linked
  def loop_repr(%__MODULE__{layout: :boxed_cons}), do: :cons
  def loop_repr(%__MODULE__{}), do: :dual

  @spec consolidate([t()]) :: t()
  def consolidate(plans) when is_list(plans) do
    cond do
      plans == [] ->
        mixed()

      Enum.all?(plans, fn %__MODULE__{layout: layout} -> layout != :mixed end) ->
        [first | _] = plans

        if Enum.all?(plans, &matching_plan?(&1, first)) do
          first
        else
          mixed()
        end

      true ->
        mixed()
    end
  end

  defp matching_plan?(%__MODULE__{} = a, %__MODULE__{} = b) do
    a.layout == b.layout and a.elem == b.elem
  end
end
