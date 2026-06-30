defmodule Ide.Auth.LoginToken do
  @moduledoc """
  One-time (or first-use) magic login link token stored as a SHA-256 hash.

  Pending tokens store `email_hash` only; the user row is created when the link
  is first opened. Legacy rows may still reference `user_id` directly.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Ide.Auth.User

  @type t :: %__MODULE__{
          id: integer() | nil,
          user_id: integer() | nil,
          email_hash: String.t() | nil,
          token_hash: String.t() | nil,
          expires_at: DateTime.t() | nil,
          used_at: DateTime.t() | nil
        }

  @type pending_changeset_attrs :: %{
          required(:email_hash) => String.t(),
          required(:token_hash) => String.t(),
          required(:expires_at) => DateTime.t()
        }

  @type changeset_attrs :: %{
          required(:user_id) => integer(),
          required(:token_hash) => String.t(),
          required(:expires_at) => DateTime.t()
        }

  schema "login_tokens" do
    belongs_to :user, User

    field :email_hash, :string
    field :token_hash, :string
    field :expires_at, :utc_datetime
    field :used_at, :utc_datetime

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @spec pending_changeset(t(), pending_changeset_attrs()) :: Ecto.Changeset.t()
  def pending_changeset(token, attrs) do
    token
    |> cast(attrs, [:email_hash, :token_hash, :expires_at])
    |> validate_required([:email_hash, :token_hash, :expires_at])
    |> unique_constraint(:token_hash)
  end

  @spec changeset(t(), changeset_attrs()) :: Ecto.Changeset.t()
  def changeset(token, attrs) do
    token
    |> cast(attrs, [:user_id, :token_hash, :expires_at])
    |> validate_required([:user_id, :token_hash, :expires_at])
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:token_hash)
  end
end
