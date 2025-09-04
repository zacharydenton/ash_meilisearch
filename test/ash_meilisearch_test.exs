defmodule AshMeilisearch.IntegrationTest do
  @moduledoc """
  Integration tests for AshMeilisearch extension.

  Tests the complete functionality using test resources similar to ash_cloak_test.
  """

  use ExUnit.Case, async: false

  alias AshMeilisearch.Test.{Post, Album}

  describe "DSL configuration" do
    test "extracts meilisearch configuration from Post" do
      index_name = AshMeilisearch.index_name(Post)
      expected_name = "ash_meilisearch_posts_test"

      assert index_name == expected_name
      assert AshMeilisearch.action_name(Post) == :search
      assert AshMeilisearch.primary_key(Post) == :id
    end

    test "extracts meilisearch configuration from Album" do
      index_name = AshMeilisearch.index_name(Album)
      expected_name = "ash_meilisearch_albums_test"

      assert index_name == expected_name
      assert AshMeilisearch.action_name(Album) == :search_albums
      assert AshMeilisearch.primary_key(Album) == :id
    end

    test "detects meilisearch is configured" do
      assert AshMeilisearch.Info.meilisearch_configured?(Post) == true
      assert AshMeilisearch.Info.meilisearch_configured?(Album) == true
    end
  end

  describe "searchable attributes" do
    test "returns searchable attributes for Post" do
      searchable = AshMeilisearch.Info.searchable_attributes(Post)
      assert searchable == ["title", "content", "tags"]
    end

    test "returns searchable attributes for Album" do
      searchable = AshMeilisearch.Info.searchable_attributes(Album)
      assert searchable == ["title", "artist", "description", "tracks.title"]
    end
  end

  describe "filterable attributes" do
    test "returns filterable attributes for Post" do
      filterable = AshMeilisearch.Info.filterable_attributes(Post)
      assert filterable == ["title", "status", "published_at"]
    end

    test "returns filterable attributes for Album" do
      filterable = AshMeilisearch.Info.filterable_attributes(Album)
      assert filterable == ["artist", "year", "genre", "tracks.title", "tracks.duration_seconds"]
    end
  end

  describe "sortable attributes" do
    test "returns sortable attributes for Post" do
      sortable = AshMeilisearch.Info.sortable_attributes(Post)
      assert sortable == ["title", "published_at", "inserted_at"]
    end

    test "returns sortable attributes for Album" do
      sortable = AshMeilisearch.Info.sortable_attributes(Album)
      assert sortable == ["title", "artist", "year", "inserted_at", "title_length", "track_count"]
    end
  end

  describe "generated actions" do
    test "adds search action to Post" do
      search_action = Ash.Resource.Info.action(Post, :search)

      assert search_action != nil
      assert search_action.type == :read
      assert search_action.name == :search

      # Check for query argument
      query_arg = Enum.find(search_action.arguments, &(&1.name == :query))
      assert query_arg != nil
    end

    test "adds custom named search action to Album" do
      search_action = Ash.Resource.Info.action(Album, :search_albums)

      assert search_action != nil
      assert search_action.type == :read
      assert search_action.name == :search_albums
    end

    test "adds reindex action to Post" do
      reindex_action = Ash.Resource.Info.action(Post, :reindex)

      assert reindex_action != nil
      assert reindex_action.type == :update
      assert reindex_action.name == :reindex
      assert reindex_action.manual != nil
    end

    test "adds configure_index action to Post" do
      configure_action = Ash.Resource.Info.action(Post, :configure_index)

      assert configure_action != nil
      assert configure_action.type == :update
      assert configure_action.name == :configure_index
      assert configure_action.manual != nil
    end
  end

  describe "generated calculations" do
    test "adds search_document calculation to Post" do
      search_doc_calc = Ash.Resource.Info.calculation(Post, :search_document)

      assert search_doc_calc != nil
      assert search_doc_calc.type == Ash.Type.Map
      assert search_doc_calc.name == :search_document
      assert search_doc_calc.public? == true
    end

    test "adds search_document calculation to Album" do
      search_doc_calc = Ash.Resource.Info.calculation(Album, :search_document)

      assert search_doc_calc != nil
      assert search_doc_calc.type == Ash.Type.Map
      assert search_doc_calc.name == :search_document
      assert search_doc_calc.public? == true
    end
  end

  describe "meilisearch fields configuration" do
    test "get_meilisearch_fields returns configured fields for Post" do
      fields = AshMeilisearch.Info.get_meilisearch_fields(Post)
      field_names = Enum.map(fields, fn {name, _type, _opts} -> name end)

      # All attributes configured in meilisearch lists should be included
      assert :title in field_names
      assert :content in field_names
      assert :tags in field_names
      assert :published_at in field_names
      assert :status in field_names
      assert :inserted_at in field_names
    end

    test "meilisearch fields have correct options" do
      fields = AshMeilisearch.Info.get_meilisearch_fields(Post)

      # Find the title field and check its options
      title_field = Enum.find(fields, fn {name, _type, _opts} -> name == :title end)
      {_name, _type, opts} = title_field

      # Title should be searchable, filterable, and sortable
      assert opts[:searchable] == true
      assert opts[:filterable] == true
      assert opts[:sortable] == true
    end
  end

  describe "load option" do
    test "loads aggregates and calculations in search action" do
      # Create test data with unique title to avoid conflicts
      unique_title = "LoadTest#{System.unique_integer([:positive])}"

      {:ok, album} =
        Album
        |> Ash.Changeset.for_create(:create, %{title: unique_title, artist: "Test Artist"})
        |> Ash.create()

      # Ensure index exists and album is indexed
      :ok = AshMeilisearch.IndexManager.ensure_index(Album)
      {:ok, _} = album |> Ash.Changeset.for_update(:reindex, %{}) |> Ash.update()
      Process.sleep(200)

      # Test search with load option
      {:ok, page} =
        Album
        |> Ash.Query.for_read(:search_albums, %{query: unique_title})
        |> Ash.Query.load([:track_count, :title_length])
        |> Ash.read()

      assert length(page.results) > 0
      first_result = List.first(page.results)

      # These should be loaded, not NotLoaded structs
      refute match?(%Ash.NotLoaded{}, first_result.track_count)
      refute match?(%Ash.NotLoaded{}, first_result.title_length)
    end
  end

  describe "validation" do
    test "validates index name is required" do
      assert_raise Spark.Error.DslError, fn ->
        defmodule InvalidResource do
          use Ash.Resource,
            domain: AshMeilisearch.Test.Domain,
            extensions: [AshMeilisearch],
            validate_domain_inclusion?: false

          attributes do
            uuid_primary_key :id
          end

          meilisearch do
            # Missing required index name
            action_name(:search)
          end
        end
      end
    end

    test "rejects composite primary keys" do
      error =
        assert_raise Spark.Error.DslError, fn ->
          defmodule CompositePrimaryKeyResource do
            use Ash.Resource,
              domain: AshMeilisearch.Test.Domain,
              extensions: [AshMeilisearch],
              validate_domain_inclusion?: false

            attributes do
              attribute :tenant_id, :uuid do
                primary_key? true
                allow_nil? false
                public? true
              end

              attribute :resource_id, :uuid do
                primary_key? true
                allow_nil? false
                public? true
              end

              attribute :title, :string do
                public? true
              end
            end

            meilisearch do
              index("composite_test")
              searchable_attributes([:title])
            end
          end
        end

      assert error.message =~ "Meilisearch only supports single-field primary keys"
      assert error.message =~ "composite primary key: [:tenant_id, :resource_id]"
    end

    test "accepts single primary key resources" do
      # This should not raise - our existing test resources prove this works
      assert AshMeilisearch.Test.Post
      assert AshMeilisearch.Test.Album
    end

    test "deep relationship chains are not supported" do
      # This test documents the current limitation and should fail
      # TODO: Remove this test when deep relationship support is implemented

      error =
        assert_raise Spark.Error.DslError, fn ->
          defmodule DeepRelationshipResource do
            use Ash.Resource,
              data_layer: Ash.DataLayer.Ets,
              domain: AshMeilisearch.Test.Domain,
              extensions: [AshMeilisearch]

            attributes do
              uuid_primary_key :id do
                generated? true
                public? true
              end

              attribute :title, :string do
                public? true
              end
            end

            relationships do
              belongs_to :author, AshMeilisearch.Test.Author do
                public? true
              end
            end

            meilisearch do
              index("deep_test")
              # This should fail - nested relationships not supported yet
              searchable_attributes([
                :title,
                # 2 levels deep
                author: [profile: [:bio, :website]]
              ])
            end
          end
        end

      # The error should indicate unsupported nested relationships
      message = error.message.message
      assert message =~ "expected atom, got:"
      assert message =~ "profile"
    end
  end
end
