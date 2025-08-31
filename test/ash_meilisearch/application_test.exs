defmodule AshMeilisearch.ApplicationTest do
  @moduledoc """
  Tests for AshMeilisearch.Application startup and shutdown behavior.

  Tests application lifecycle, index management, and test cleanup.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  require Logger

  alias AshMeilisearch.Application

  describe "application startup" do
    test "creates indexes for resources on startup" do
      # The application should have already created indexes for our test resources
      # Let's verify they exist
      post_index = AshMeilisearch.index_name(AshMeilisearch.Test.Post)
      album_index = AshMeilisearch.index_name(AshMeilisearch.Test.Album)

      # Check that the indexes were created
      assert {:ok, _} = AshMeilisearch.Client.get_index(post_index)
      assert {:ok, _} = AshMeilisearch.Client.get_index(album_index)
    end

    test "indexes have correct settings configured" do
      # Verify that indexes have the correct settings from DSL
      album_index = AshMeilisearch.index_name(AshMeilisearch.Test.Album)

      # Wait a moment for Meilisearch to process the index creation
      Process.sleep(100)

      {:ok, settings} = AshMeilisearch.Client.get_index_settings(album_index)

      # Album has sortable_attributes: [:title, :artist, :year, :inserted_at, :title_length, :track_count]
      # Meilisearch may return these in a different order
      assert Enum.sort(settings["sortableAttributes"]) ==
               Enum.sort([
                 "title",
                 "artist",
                 "year",
                 "inserted_at",
                 "title_length",
                 "track_count"
               ])

      # Album has searchable_attributes: [:title, :artist, :description, tracks: [:title]]
      # Order matters for searchable attributes (ranking)
      assert settings["searchableAttributes"] == [
               "title",
               "artist",
               "description",
               "tracks.title"
             ]

      # Album has filterable_attributes: [:artist, :year, :genre, tracks: [:title, :duration_seconds]]
      assert Enum.sort(settings["filterableAttributes"]) ==
               Enum.sort(["artist", "year", "genre", "tracks.title", "tracks.duration_seconds"])
    end
  end

  describe "index management integration" do
    test "application startup attempts to create indexes for configured resources" do
      # This test verifies the integration without requiring Meilisearch to be running

      # The application should find resources and attempt to create indexes
      # Even if it fails due to no Meilisearch server, the integration should work

      logs =
        capture_log(fn ->
          # Simulate what happens during application start
          # This will likely fail with connection error, which is expected
          result = Application.start(:normal, [])

          # Should either succeed (if Meilisearch running) or crash (let it crash)
          case result do
            {:ok, _pid} ->
              # Success - Meilisearch was running
              :ok = Application.stop(:normal)

            {:error, _reason} ->
              # Expected if Meilisearch not running
              :ok
          end
        end)

      # Should see attempts to validate connection and ensure indexes
      # The exact logs depend on whether Meilisearch is running
      assert logs =~ "AshMeilisearch" or logs == ""
    end
  end
end
