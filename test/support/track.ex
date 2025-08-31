defmodule AshMeilisearch.Test.Track do
  @moduledoc """
  Test track resource for testing Album aggregates.
  """

  use Ash.Resource,
    domain: AshMeilisearch.Test.Domain,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  actions do
    default_accept [:title, :duration_seconds, :album_id]
    defaults [:create, :read, :update, :destroy]
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :duration_seconds, :integer do
      public? true
    end

    attribute :album_id, :uuid do
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :album, AshMeilisearch.Test.Album
  end
end
