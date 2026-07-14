defmodule Elmc.Backend.Plan.Lower.MaybePayload do
  @moduledoc false

  alias Elmc.Backend.Plan.Context
  alias Elmc.Backend.Plan.Types

  @payload_var "__maybe_payload__"

  @spec payload_var() :: String.t()
  def payload_var, do: @payload_var

  @spec inner_type(String.t() | nil) :: String.t() | nil
  def inner_type(type) when is_binary(type) do
    trimmed = String.trim(type)

    case Regex.run(~r/^Maybe\s+(.+)$/s, trimmed) do
      [_, inner] -> String.trim(inner)
      _ -> nil
    end
  end

  def inner_type(_), do: nil

  @spec inner_type_from_maybe_expr(Types.ir_expr(), Context.t()) :: String.t() | nil
  def inner_type_from_maybe_expr(%{op: :var, name: name}, ctx) when is_binary(name) do
    ctx |> Context.local_type(name) |> inner_type()
  end

  def inner_type_from_maybe_expr(_, _), do: nil

  @spec ctx_for_payload(Types.ir_expr(), Context.t()) :: Context.t()
  def ctx_for_payload(maybe_expr, ctx) do
    case inner_type_from_maybe_expr(maybe_expr, ctx) do
      inner when is_binary(inner) ->
        Context.put_local_type(ctx, @payload_var, inner)

      _ ->
        ctx
    end
  end

  @spec payload_base_expr(Context.t()) :: Types.ir_expr() | nil
  def payload_base_expr(ctx) do
    if Context.local_type(ctx, @payload_var) do
      %{op: :var, name: @payload_var}
    else
      nil
    end
  end
end
