defmodule Ide.Auth.User do
  @moduledoc """
  Authenticated IDE user.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          firebase_uid: String.t() | nil,
          email: String.t() | nil,
          display_name: String.t() | nil
        }

  schema "users" do
    field :firebase_uid, :string
    field :email, :string
    field :display_name, :string
    has_many :projects, Ide.Projects.Project, foreign_key: :owner_id

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:firebase_uid, :email, :display_name])
    |> validate_required([:firebase_uid])
    |> unique_constraint(:firebase_uid)
  end
end
