defmodule Ide.Auth.LoginToken do
  @moduledoc """
  One-time (or first-use) magic login link token stored as a SHA-256 hash.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Ide.Auth.User

  @type t :: %__MODULE__{
          id: integer() | nil,
          user_id: integer() | nil,
          token_hash: String.t() | nil,
          expires_at: DateTime.t() | nil,
          used_at: DateTime.t() | nil
        }

  schema "login_tokens" do
    belongs_to :user, User

    field :token_hash, :string
    field :expires_at, :utc_datetime
    field :used_at, :utc_datetime

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(token, attrs) do
    token
    |> cast(attrs, [:user_id, :token_hash, :expires_at])
    |> validate_required([:user_id, :token_hash, :expires_at])
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:token_hash)
  end
end
