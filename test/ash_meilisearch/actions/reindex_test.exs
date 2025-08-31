defmodule AshMeilisearch.Actions.ReindexTest do
  @moduledoc """
  Tests for the AshMeilisearch.Actions.Reindex manual action.

  This tests the individual record reindexing functionality that updates
  single records in the Meilisearch index.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  require Logger
  require Ash.Expr
  require Ash.Query

  alias AshMeilisearch.Test.{Album, Post}

  setup do
    # Clean up test indexes before each test
    album_index = AshMeilisearch.index_name(Album)
    post_index = AshMeilisearch.index_name(Post)

    if album_index do
      AshMeilisearch.Client.delete_index(album_index)
      # Allow time for deletion
      Process.sleep(100)
    end

    if post_index do
      AshMeilisearch.Client.delete_index(post_index)
      # Allow time for deletion
      Process.sleep(100)
    end

    :ok
  end

  describe "reindex action" do
    test "successfully reindexes a single album record" do
      title_id = System.unique_integer([:positive])
      artist_id = System.unique_integer([:positive])
      year_id = System.unique_integer([:positive])

      unique_title = "SingleReindex#{title_id}"
      unique_artist = "Artist#{artist_id}"
      # 2000-2024
      unique_year = 2000 + rem(year_id, 25)

      # Create an album
      {:ok, album} =
        Album
        |> Ash.Changeset.for_create(:create, %{
          title: unique_title,
          artist: unique_artist,
          year: unique_year
        })
        |> Ash.create()

      # Ensure index exists first
      :ok = AshMeilisearch.IndexManager.ensure_index(Album)
      # Allow index to be created
      Process.sleep(100)

      # Reindex the specific album
      result =
        album
        |> Ash.Changeset.for_update(:reindex, %{})
        |> Ash.update()

      assert {:ok, updated_album} = result
      assert updated_album.id == album.id
      assert updated_album.title == unique_title

      # Verify the document was added to Meilisearch using the search action with filters
      # Allow time for indexing
      Process.sleep(500)

      {:ok, search_results} =
        Album
        |> Ash.Query.for_read(:search_albums, %{query: unique_title})
        |> Ash.Query.filter(artist == ^unique_artist and year == ^unique_year)
        |> Ash.read()

      assert length(search_results.results) >= 1
      found_album = Enum.find(search_results.results, fn a -> a.id == album.id end)
      assert found_album != nil
      assert found_album.title == unique_title
      assert found_album.artist == unique_artist
    end

    test "reindex only affects the specific record, not all records" do
      # Create two albums with unique identifiers
      id1 = System.unique_integer([:positive])
      id2 = System.unique_integer([:positive])

      unique_title1 = "AlbumOne#{id1}"
      unique_artist1 = "ArtistOne#{id1}"
      unique_title2 = "AlbumTwo#{id2}"
      unique_artist2 = "ArtistTwo#{id2}"

      {:ok, album1} =
        Album
        |> Ash.Changeset.for_create(:create, %{
          title: unique_title1,
          artist: unique_artist1,
          year: 2023
        })
        |> Ash.create()

      {:ok, album2} =
        Album
        |> Ash.Changeset.for_create(:create, %{
          title: unique_title2,
          artist: unique_artist2,
          year: 2024
        })
        |> Ash.create()

      # Ensure index exists
      :ok = AshMeilisearch.IndexManager.ensure_index(Album)

      # Manually add album1 to index first
      {:ok, album1_with_doc} =
        Album
        |> Ash.Query.filter(Ash.Expr.expr(id == ^album1.id))
        |> Ash.Query.load(:search_document)
        |> Ash.read_one()

      index_name = AshMeilisearch.index_name(Album)

      {:ok, _} =
        AshMeilisearch.Client.index_documents(index_name, [album1_with_doc.search_document])

      Process.sleep(200)

      # Reindex only album2
      logs =
        capture_log(fn ->
          {:ok, _} =
            album2
            |> Ash.Changeset.for_update(:reindex, %{})
            |> Ash.update()
        end)

      # Verify logs show single record processing
      assert logs =~ "Starting reindex for record #{album2.id}"
      refute logs =~ "Loading all records"
      refute logs =~ "Clearing index"

      # Allow time for indexing
      Process.sleep(200)

      # Verify both albums are findable using search action with filters
      {:ok, album1_results} =
        Album
        |> Ash.Query.for_read(:search_albums, %{query: unique_title1})
        |> Ash.Query.filter(artist == ^unique_artist1)
        |> Ash.read()

      {:ok, album2_results} =
        Album
        |> Ash.Query.for_read(:search_albums, %{query: unique_title2})
        |> Ash.Query.filter(artist == ^unique_artist2)
        |> Ash.read()

      # Both should be found
      assert length(album1_results.results) >= 1
      assert length(album2_results.results) >= 1

      found_album1 = Enum.find(album1_results.results, fn a -> a.id == album1.id end)
      found_album2 = Enum.find(album2_results.results, fn a -> a.id == album2.id end)

      assert found_album1 != nil
      assert found_album2 != nil
      assert found_album1.title == unique_title1
      assert found_album2.title == unique_title2
    end

    test "returns error when record not found" do
      # Create a dummy record struct with fake ID to test reindex failure
      fake_album = struct(Album, %{id: Ash.UUID.generate()})

      result =
        fake_album
        |> Ash.Changeset.for_update(:reindex, %{})
        |> Ash.update()

      assert {:error, error} = result
      assert Exception.message(error) =~ "Record not found"
    end

    test "handles search document generation errors gracefully" do
      # Mock failure by trying to reindex with invalid UUID
      # This tests error handling path
      logs =
        capture_log([level: :error], fn ->
          # Force an error by using invalid query
          fake_album = struct(Album, %{id: "invalid-uuid"})

          result =
            fake_album
            |> Ash.Changeset.for_update(:reindex, %{})
            |> Ash.update()

          assert {:error, _error} = result
        end)

      assert logs =~ "Reindex failed"
    end

    test "updates existing document in index" do
      # Generate unique identifiers
      title_id = System.unique_integer([:positive])
      artist_id = System.unique_integer([:positive])
      year_id = System.unique_integer([:positive])

      unique_title = "UpdateTest#{title_id}"
      unique_artist = "Artist#{artist_id}"
      # 2000-2024
      unique_year = 2000 + rem(year_id, 25)

      # Create and initially index an album
      {:ok, album} =
        Album
        |> Ash.Changeset.for_create(:create, %{
          title: unique_title,
          artist: unique_artist,
          year: unique_year
        })
        |> Ash.create()

      :ok = AshMeilisearch.IndexManager.ensure_index(Album)

      # Initial reindex
      {:ok, _} =
        album
        |> Ash.Changeset.for_update(:reindex, %{})
        |> Ash.update()

      Process.sleep(200)

      # Update the album title
      updated_title = "Updated#{unique_title}"

      {:ok, updated_album} =
        album
        |> Ash.Changeset.for_update(:update, %{title: updated_title})
        |> Ash.update()

      # Reindex with new data
      {:ok, _} =
        updated_album
        |> Ash.Changeset.for_update(:reindex, %{})
        |> Ash.update()

      Process.sleep(200)

      # Search should find updated title
      {:ok, updated_results} =
        Album
        |> Ash.Query.for_read(:search_albums, %{query: updated_title})
        |> Ash.Query.filter(artist == ^unique_artist and year == ^unique_year)
        |> Ash.read()

      assert length(updated_results.results) >= 1
      found_album = Enum.find(updated_results.results, fn a -> a.id == album.id end)
      assert found_album != nil
      assert found_album.title == updated_title

      # Should not find old title
      {:ok, old_results} =
        Album
        |> Ash.Query.for_read(:search_albums, %{query: unique_title})
        |> Ash.Query.filter(artist == ^unique_artist and year == ^unique_year)
        |> Ash.read()

      # Old title should not be found since document was updated
      old_album = Enum.find(old_results.results, fn a -> a.id == album.id end)
      assert old_album == nil
    end
  end
end
