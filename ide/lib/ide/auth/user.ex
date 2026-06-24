defmodule Ide.Auth.User do
  @moduledoc """
  Authenticated IDE user.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Ide.Auth.EmailHash
  alias Ide.Auth.LoginToken

  @type t :: %__MODULE__{
          id: integer() | nil,
          firebase_uid: String.t() | nil,
          email_hash: String.t() | nil,
          display_name: String.t() | nil,
          password_hash: String.t() | nil
        }

  @type changeset_attrs :: %{
          optional(:firebase_uid) => String.t(),
          optional(:display_name) => String.t()
        }

  @type email_changeset_attrs :: %{
          required(:email) => String.t(),
          optional(:display_name) => String.t()
        }

  schema "users" do
    field :firebase_uid, :string
    field :email_hash, :string
    field :email, :string, virtual: true
    field :display_name, :string
    field :password_hash, :string

    has_many :login_tokens, LoginToken
    has_many :projects, Ide.Projects.Project, foreign_key: :owner_id

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), changeset_attrs()) :: Ecto.Changeset.t()
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:firebase_uid, :display_name])
    |> validate_required([:firebase_uid])
    |> unique_constraint(:firebase_uid, name: :users_firebase_uid_index)
  end

  @spec email_changeset(t(), email_changeset_attrs()) :: Ecto.Changeset.t()
  def email_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :display_name])
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email address")
    |> update_change(:email, &normalize_email/1)
    |> hash_email_change()
    |> unique_constraint(:email_hash, name: :users_email_hash_index)
  end

  @spec normalize_email(String.t()) :: String.t()
  def normalize_email(email) when is_binary(email), do: String.downcase(String.trim(email))

  defp hash_email_change(changeset) do
    case get_change(changeset, :email) do
      nil -> changeset
      email -> put_change(changeset, :email_hash, EmailHash.hash(email))
    end
  end
end
