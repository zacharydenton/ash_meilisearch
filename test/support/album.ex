defmodule AshMeilisearch.Test.Album do
  @moduledoc """
  Test album resource for AshMeilisearch integration tests.

  Demonstrates a different meilisearch configuration.
  """

  use Ash.Resource,
    domain: AshMeilisearch.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshMeilisearch]

  ets do
    private? true
  end

  meilisearch do
    index("ash_meilisearch_albums")
    action_name(:search_albums)
    searchable_attributes([:title, :artist, :description, tracks: [:title]])
    filterable_attributes([:artist, :year, :genre, tracks: [:title, :duration_seconds]])
    sortable_attributes([:title, :artist, :year, :inserted_at, :title_length, :track_count])
  end

  actions do
    default_accept [:title, :artist, :year, :genre, :description]
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

    attribute :artist, :string do
      public? true
    end

    attribute :year, :integer do
      public? true
    end

    attribute :genre, :string do
      public? true
    end

    attribute :description, :string do
      public? true
    end

    create_timestamp :inserted_at, public?: true
  end

  relationships do
    has_many :tracks, AshMeilisearch.Test.Track
  end

  aggregates do
    count :track_count, :tracks do
      public? true
    end
  end

  calculations do
    calculate :title_length, :integer, expr(string_length(title)) do
      public? true
    end
  end
end
