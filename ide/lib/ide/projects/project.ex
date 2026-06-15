defmodule Ide.Projects.Project do
  @moduledoc """
  Project metadata persisted by the IDE.
  """

  use Ecto.Schema
  import Ecto.Query, only: [from: 2, dynamic: 2]
  import Ecto.Changeset

  alias Ide.ProjectTemplates
  alias Ide.Projects.Types
  alias Ide.Repo

  @target_types ~w(app watchface companion)

  @type t :: %__MODULE__{
          id: integer() | nil,
          owner_id: integer() | nil,
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
          store_metadata_cache: Types.store_metadata() | nil,
          package_metadata_cache: Types.package_metadata() | nil,
          release_defaults: Types.release_defaults() | nil,
          github: Types.github_config() | nil,
          debugger_settings: Types.debugger_settings() | nil,
          template: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "projects" do
    belongs_to :owner, Ide.Auth.User
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
    field :package_metadata_cache, :map, default: %{}
    field :release_defaults, :map, default: %{}
    field :github, :map, default: %{}
    field :debugger_settings, :map, default: %{}
    field :template, :string, virtual: true

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for project create/update.
  """
  @spec changeset(t() | %__MODULE__{}, Types.project_attrs()) :: Ecto.Changeset.t()
  def changeset(project, attrs) do
    project
    |> cast(attrs, [
      :name,
      :owner_id,
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
      :package_metadata_cache,
      :release_defaults,
      :github,
      :debugger_settings
    ])
    |> validate_required([:name, :slug, :target_type, :source_roots])
    |> validate_format(:slug, ~r/^[a-z0-9][a-z0-9\-_]*$/)
    |> validate_length(:source_roots, min: 1)
    |> validate_inclusion(:target_type, @target_types)
    |> validate_change(:template, fn :template, value ->
      if is_nil(value) or value in ProjectTemplates.template_keys(),
        do: [],
        else: [template: "is invalid"]
    end)
    |> validate_slug_available()
    |> unique_constraint(:slug,
      name: :projects_slug_index,
      message: "is already in use by another project"
    )
    |> unique_constraint(:slug,
      name: :projects_owner_id_slug_index,
      message: "is already in use by another of your projects"
    )
    |> unique_constraint(:slug,
      name: :projects_local_slug_index,
      message: "is already in use by another project"
    )
  end

  defp validate_slug_available(changeset) do
    slug = get_change(changeset, :slug) || get_field(changeset, :slug)
    owner_id = get_change(changeset, :owner_id) || get_field(changeset, :owner_id)
    project_id = get_field(changeset, :id)

    if is_binary(slug) and slug != "" do
      query =
        from p in __MODULE__,
          where: p.slug == ^slug,
          where: ^owner_scope(owner_id)

      query =
        if project_id do
          from p in query, where: p.id != ^project_id
        else
          query
        end

      if Repo.exists?(query) do
        add_error(changeset, :slug, "is already in use. Choose a different slug.")
      else
        changeset
      end
    else
      changeset
    end
  end

  defp owner_scope(nil), do: dynamic([p], is_nil(p.owner_id))
  defp owner_scope(owner_id), do: dynamic([p], p.owner_id == ^owner_id)
end
