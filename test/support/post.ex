defmodule AshMeilisearch.Test.Post do
  @moduledoc """
  Test resource for AshMeilisearch integration tests.
  """

  use Ash.Resource,
    domain: AshMeilisearch.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshMeilisearch]

  ets do
    private? true
  end

  meilisearch do
    index("ash_meilisearch_posts")
    action_name(:search)
    searchable_attributes([:title, :content, :tags])
    filterable_attributes([:title, :status, :published_at])
    sortable_attributes([:title, :published_at, :inserted_at])
  end

  actions do
    default_accept [:title, :content, :published_at, :status, :tags]
    defaults [:create, :read, :update, :destroy]
  end

  changes do
    change AshMeilisearch.Changes.UpsertSearchDocument, on: [:create, :update]
    change AshMeilisearch.Changes.DeleteSearchDocument, on: [:destroy]
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :content, :string do
      public? true
    end

    attribute :published_at, :utc_datetime do
      public? true
    end

    attribute :status, :atom do
      constraints one_of: [:draft, :published, :archived]
      default :draft
      public? true
    end

    attribute :tags, {:array, :string} do
      public? true
      default []
    end

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end
end
