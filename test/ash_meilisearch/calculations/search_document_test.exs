defmodule AshMeilisearch.Calculations.SearchDocumentTest do
  use ExUnit.Case, async: true

  alias AshMeilisearch.Calculations.SearchDocument
  alias AshMeilisearch.Test.{Album, Track, Post}

  describe "format_document/2 with real Ash resources" do
    setup do
      # Create test album
      album =
        Album
        |> Ash.Changeset.for_create(:create, %{title: "Test Album", artist: "Test Artist"})
        |> Ash.create!()

      %{album: album}
    end

    test "creates basic document with Album resource", %{album: album} do
      meilisearch_fields = []

      document = SearchDocument.format_document(album, meilisearch_fields, :id)

      assert document["id"] == album.id
      assert is_map(document)
    end

    test "includes configured attribute fields from Album", %{album: album} do
      # Update album with more attributes
      album =
        album
        |> Ash.Changeset.for_update(:update, %{
          year: 2023,
          description: "Great album"
        })
        |> Ash.update!()

      meilisearch_fields = [
        {:title, :attribute, []},
        {:artist, :attribute, []},
        {:year, :attribute, []},
        {:description, :attribute, []}
      ]

      document = SearchDocument.format_document(album, meilisearch_fields, :id)

      assert document["id"] == album.id
      assert document["title"] == "Test Album"
      assert document["artist"] == "Test Artist"
      assert document["year"] == 2023
      assert document["description"] == "Great album"
    end

    test "includes configured calculation fields from Album", %{album: album} do
      # Load the calculation
      album = Ash.load!(album, [:title_length])

      meilisearch_fields = [
        {:title, :attribute, []},
        {:title_length, :calculation, []}
      ]

      document = SearchDocument.format_document(album, meilisearch_fields, :id)

      assert document["id"] == album.id
      assert document["title"] == "Test Album"
      # length of "Test Album"
      assert document["title_length"] == 10
    end

    test "includes configured aggregate fields from Album", %{album: album} do
      # Create some tracks for the album
      Track
      |> Ash.Changeset.for_create(:create, %{
        title: "Song 1",
        duration_seconds: 180,
        album_id: album.id
      })
      |> Ash.create!()

      Track
      |> Ash.Changeset.for_create(:create, %{
        title: "Song 2",
        duration_seconds: 240,
        album_id: album.id
      })
      |> Ash.create!()

      # Load the aggregate
      album = Ash.load!(album, [:track_count])

      meilisearch_fields = [
        {:title, :attribute, []},
        {:track_count, :aggregate, []}
      ]

      document = SearchDocument.format_document(album, meilisearch_fields, :id)

      assert document["id"] == album.id
      assert document["title"] == "Test Album"
      assert document["track_count"] == 2
    end

    test "includes relationship fields from Album with tracks", %{album: album} do
      # Create some tracks for the album
      Track
      |> Ash.Changeset.for_create(:create, %{
        title: "Song 1",
        duration_seconds: 180,
        album_id: album.id
      })
      |> Ash.create!()

      Track
      |> Ash.Changeset.for_create(:create, %{
        title: "Song 2",
        duration_seconds: 240,
        album_id: album.id
      })
      |> Ash.create!()

      # Load the relationship
      album = Ash.load!(album, tracks: [:title, :duration_seconds])

      meilisearch_fields = [
        {:title, :attribute, []},
        {{:tracks, [:title, :duration_seconds]}, :relationship, []}
      ]

      document = SearchDocument.format_document(album, meilisearch_fields, :id)

      assert document["id"] == album.id
      assert document["title"] == "Test Album"

      expected_tracks = [
        %{title: "Song 1", duration_seconds: 180},
        %{title: "Song 2", duration_seconds: 240}
      ]

      # Sort both arrays by title for consistent comparison
      actual_tracks = Enum.sort_by(document["tracks"], & &1[:title])
      expected_tracks = Enum.sort_by(expected_tracks, & &1[:title])

      assert actual_tracks == expected_tracks
    end
  end

  describe "relationship handling" do
    setup do
      album =
        Album
        |> Ash.Changeset.for_create(:create, %{
          title: "Test Album",
          artist: "Test Artist",
          year: 2023
        })
        |> Ash.create!()

      track =
        Track
        |> Ash.Changeset.for_create(:create, %{
          title: "Song 1",
          duration_seconds: 180,
          album_id: album.id
        })
        |> Ash.create!()

      %{album: album, track: track}
    end

    test "includes single relationship field from Track to Album", %{track: track} do
      # Load the relationship
      track = Ash.load!(track, album: [:title, :year])

      meilisearch_fields = [
        {:title, :attribute, []},
        {{:album, [:title, :year]}, :relationship, []}
      ]

      document = SearchDocument.format_document(track, meilisearch_fields, :id)

      assert document["id"] == track.id
      assert document["title"] == "Song 1"
      assert document["album"] == %{title: "Test Album", year: 2023}
    end

    test "handles Album has_many tracks relationship", %{album: album} do
      # Create another track
      Track
      |> Ash.Changeset.for_create(:create, %{
        title: "Song 2",
        duration_seconds: 240,
        album_id: album.id
      })
      |> Ash.create!()

      album = Ash.load!(album, tracks: [:title, :duration_seconds])

      result = SearchDocument.get_relationship_value(album, :tracks, [:title, :duration_seconds])

      {:ok, tracks} = result
      tracks_sorted = Enum.sort_by(tracks, & &1[:title])

      expected = [
        %{title: "Song 1", duration_seconds: 180},
        %{title: "Song 2", duration_seconds: 240}
      ]

      assert tracks_sorted == expected
    end

    test "handles Track belongs_to album relationship", %{track: track} do
      track = Ash.load!(track, album: [:title, :year])

      result = SearchDocument.get_relationship_value(track, :album, [:title, :year])

      assert result == {:ok, %{title: "Test Album", year: 2023}}
    end

    test "handles empty has_many relationship" do
      empty_album =
        Album
        |> Ash.Changeset.for_create(:create, %{title: "Empty Album", artist: "No Tracks"})
        |> Ash.create!()

      empty_album = Ash.load!(empty_album, [:tracks])

      result = SearchDocument.get_relationship_value(empty_album, :tracks, [:title])

      assert result == {:ok, []}
    end

    test "handles not loaded relationship" do
      album =
        Album
        |> Ash.Changeset.for_create(:create, %{title: "Unloaded Album", artist: "Test Artist"})
        |> Ash.create!()

      # Don't load tracks relationship
      result = SearchDocument.get_relationship_value(album, :tracks, [:title])

      assert result == {:error, :not_loaded}
    end
  end

  describe "load/3 for field configuration" do
    test "loads only calculation and aggregate fields, not attributes" do
      meilisearch_fields = [
        # Should NOT be loaded
        {:title, :attribute, []},
        {:artist, :attribute, []},
        # Should be loaded
        {:title_length, :calculation, []},
        {:track_count, :aggregate, []},
        # Should be loaded - relationship 
        {{:tracks, [:title, :duration_seconds]}, :relationship, []}
      ]

      opts = [meilisearch_fields: meilisearch_fields]
      loads = SearchDocument.load(nil, opts, nil)

      expected = [:title_length, :track_count, {:tracks, [:title, :duration_seconds]}]
      assert Enum.sort(loads) == Enum.sort(expected)
    end

    test "handles complex field configuration" do
      meilisearch_fields = [
        {:title, :attribute, []},
        {:title_length, :calculation, []},
        {:track_count, :aggregate, []},
        {{:tracks, [:title]}, :relationship, []}
      ]

      opts = [meilisearch_fields: meilisearch_fields]
      loads = SearchDocument.load(nil, opts, nil)

      expected = [:title_length, :track_count, {:tracks, [:title]}]
      assert Enum.sort(loads) == Enum.sort(expected)
    end
  end

  describe "type conversions for Meilisearch compatibility" do
    test "converts atoms to strings in Post status" do
      # Using Post resource which has an atom status field
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "Test Post", status: :published})
        |> Ash.create!()

      meilisearch_fields = [
        {:status, :attribute, []}
      ]

      document = SearchDocument.format_document(post, meilisearch_fields, :id)

      assert document["status"] == "published"
    end

    test "converts DateTime to unix timestamp" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{
          title: "Test Post",
          published_at: ~U[2025-08-31 10:59:07.817279Z]
        })
        |> Ash.create!()

      meilisearch_fields = [
        {:published_at, :attribute, []}
      ]

      document = SearchDocument.format_document(post, meilisearch_fields, :id)

      assert document["published_at"] == 1_756_637_947
    end

    test "keeps strings and integers unchanged" do
      album =
        Album
        |> Ash.Changeset.for_create(:create, %{
          title: "Test Album",
          artist: "Test Artist",
          year: 2023
        })
        |> Ash.create!()

      meilisearch_fields = [
        {:title, :attribute, []},
        {:year, :attribute, []}
      ]

      document = SearchDocument.format_document(album, meilisearch_fields, :id)

      assert document["title"] == "Test Album"
      assert document["year"] == 2023
    end

    test "handles mixed type conversions in real resource" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{
          title: "Test Post",
          content: "Sample content",
          status: :published,
          published_at: ~U[2025-08-31 10:59:07Z],
          tags: ["elixir", "ash"]
        })
        |> Ash.create!()

      meilisearch_fields = [
        {:title, :attribute, []},
        {:content, :attribute, []},
        {:status, :attribute, []},
        {:published_at, :attribute, []},
        {:tags, :attribute, []}
      ]

      document = SearchDocument.format_document(post, meilisearch_fields, :id)

      assert document["title"] == "Test Post"
      assert document["content"] == "Sample content"
      assert document["status"] == "published"
      assert document["published_at"] == DateTime.to_unix(~U[2025-08-31 10:59:07Z])
      assert document["tags"] == ["elixir", "ash"]
    end
  end

  describe "calculate/3 with real resources" do
    test "processes list of Album records" do
      album1 =
        Album
        |> Ash.Changeset.for_create(:create, %{title: "First Album", artist: "Artist 1"})
        |> Ash.create!()

      album2 =
        Album
        |> Ash.Changeset.for_create(:create, %{title: "Second Album", artist: "Artist 2"})
        |> Ash.create!()

      meilisearch_fields = [
        {:title, :attribute, []},
        {:artist, :attribute, []}
      ]

      {:ok, documents} =
        SearchDocument.calculate([album1, album2], [meilisearch_fields: meilisearch_fields], nil)

      assert length(documents) == 2

      doc1 = Enum.find(documents, &(&1["id"] == album1.id))
      doc2 = Enum.find(documents, &(&1["id"] == album2.id))

      assert doc1["title"] == "First Album"
      assert doc1["artist"] == "Artist 1"
      assert doc2["title"] == "Second Album"
      assert doc2["artist"] == "Artist 2"
    end

    test "handles empty record list" do
      {:ok, documents} = SearchDocument.calculate([], [meilisearch_fields: []], nil)

      assert documents == []
    end
  end

  # Keep some basic unit tests for edge cases that don't require full resources
  describe "edge case handling" do
    test "skips fields that are not loaded" do
      record = %{id: "123", title: %Ash.NotLoaded{}}

      meilisearch_fields = [
        {:title, :attribute, []}
      ]

      document = SearchDocument.format_document(record, meilisearch_fields, :id)

      assert document["id"] == "123"
      assert Map.has_key?(document, "title") == false
    end

    test "handles missing fields gracefully" do
      record = %{id: "123"}

      meilisearch_fields = [
        {:missing_field, :attribute, []}
      ]

      document = SearchDocument.format_document(record, meilisearch_fields, :id)

      assert document["id"] == "123"
      assert Map.has_key?(document, "missing_field") == false
    end
  end
end
