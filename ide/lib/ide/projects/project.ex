defmodule Ide.Projects.Project do
  @moduledoc """
  Project metadata persisted by the IDE.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @target_types ~w(app watchface companion)
  @template_keys ~w(starter watchface-digital watchface-analog watchface-tutorial-complete watchface-yes game-basic game-tiny-bird game-greeneys-run game-2048)

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          slug: String.t() | nil,
          target_type: String.t() | nil,
          source_roots: [String.t()] | nil,
          active: boolean() | nil,
          store_app_id: String.t() | nil,
          app_uuid: String.t() | nil,
          latest_published_version: String.t() | nil,
          latest_published_at: DateTime.t() | nil,
          store_sync_at: DateTime.t() | nil,
          store_metadata_cache: map() | nil,
          release_defaults: map() | nil,
          github: map() | nil,
          debugger_settings: map() | nil,
          template: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "projects" do
    field :name, :string
    field :slug, :string
    field :target_type, :string
    field :source_roots, {:array, :string}, default: []
    field :active, :boolean, default: false
    field :store_app_id, :string
    field :app_uuid, :string
    field :latest_published_version, :string
    field :latest_published_at, :utc_datetime
    field :store_sync_at, :utc_datetime
    field :store_metadata_cache, :map, default: %{}
    field :release_defaults, :map, default: %{}
    field :github, :map, default: %{}
    field :debugger_settings, :map, default: %{}
    field :template, :string, virtual: true

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for project create/update.
  """
  @spec changeset(term(), term()) :: term()
  def changeset(project, attrs) do
    project
    |> cast(attrs, [
      :name,
      :slug,
      :target_type,
      :source_roots,
      :active,
      :template,
      :store_app_id,
      :app_uuid,
      :latest_published_version,
      :latest_published_at,
      :store_sync_at,
      :store_metadata_cache,
      :release_defaults,
      :github,
      :debugger_settings
    ])
    |> validate_required([:name, :slug, :target_type, :source_roots])
    |> validate_format(:slug, ~r/^[a-z0-9][a-z0-9\-_]*$/)
    |> validate_length(:source_roots, min: 1)
    |> validate_inclusion(:target_type, @target_types)
    |> validate_change(:template, fn :template, value ->
      if is_nil(value) or value in @template_keys, do: [], else: [template: "is invalid"]
    end)
    |> unique_constraint(:slug)
  end
end
