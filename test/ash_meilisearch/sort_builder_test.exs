defmodule AshMeilisearch.SortBuilderTest do
  use ExUnit.Case, async: true

  alias AshMeilisearch.SortBuilder
  alias AshMeilisearch.Test.Album

  describe "build_sort/2" do
    test "handles empty sort list" do
      assert SortBuilder.build_sort([], Album) == []
    end

    test "handles nil sort" do
      assert SortBuilder.build_sort(nil, Album) == []
    end

    test "converts sortable field sorts" do
      assert SortBuilder.build_sort([title: :asc], Album) == ["title:asc"]
      assert SortBuilder.build_sort([title: :desc], Album) == ["title:desc"]
      assert SortBuilder.build_sort([year: :asc], Album) == ["year:asc"]
    end

    test "filters out unsortable fields" do
      # 'id' and 'genre' are not in sortable_attributes for Album
      sorts = [title: :asc, id: :desc, genre: :asc, artist: :desc]
      expected = ["title:asc", "artist:desc"]

      assert SortBuilder.build_sort(sorts, Album) == expected
    end

    test "returns empty list when all fields are unsortable" do
      # All these fields are not in sortable_attributes
      sorts = [id: :asc, genre: :desc, description: :asc]
      expected = []

      assert SortBuilder.build_sort(sorts, Album) == expected
    end

    test "handles mixed sortable and unsortable fields" do
      sorts = [
        # sortable
        {:title, :asc},
        # not sortable
        {:genre, :desc},
        # sortable
        {:year, :asc},
        # not sortable
        {:description, :desc},
        # sortable
        {:artist, :asc}
      ]

      expected = [
        "title:asc",
        "year:asc",
        "artist:asc"
      ]

      assert SortBuilder.build_sort(sorts, Album) == expected
    end

    test "handles unknown sort specifications" do
      # Test with an unknown sort specification structure
      sorts = [{%{unknown: :spec}, :asc}, {:title, :desc}]
      expected = ["title:desc"]

      assert SortBuilder.build_sort(sorts, Album) == expected
    end
  end

  describe "convert_sort_field/2" do
    setup do
      # Get sortable attributes for Album: ["title", "artist", "year", "inserted_at"]
      sortable_attrs = ["title", "artist", "year", "inserted_at"]
      {:ok, sortable_attrs: sortable_attrs}
    end

    test "converts sortable atom field", %{sortable_attrs: sortable_attrs} do
      assert SortBuilder.convert_sort_field({:title, :asc}, sortable_attrs) == "title:asc"
      assert SortBuilder.convert_sort_field({:artist, :desc}, sortable_attrs) == "artist:desc"
    end

    test "filters out unsortable atom field", %{sortable_attrs: sortable_attrs} do
      assert SortBuilder.convert_sort_field({:genre, :asc}, sortable_attrs) == nil
      assert SortBuilder.convert_sort_field({:id, :desc}, sortable_attrs) == nil
    end

    test "converts relationship tuple when sortable" do
      # Test with a hypothetical sortable relationship field
      sortable_attrs = ["author.name", "category.title"]

      assert SortBuilder.convert_sort_field({{:author, :name}, :asc}, sortable_attrs) ==
               "author.name:asc"
    end

    test "filters out unsortable relationship tuple" do
      sortable_attrs = ["title", "artist"]
      assert SortBuilder.convert_sort_field({{:author, :name}, :asc}, sortable_attrs) == nil
    end

    test "converts field path list when sortable" do
      sortable_attrs = ["author.profile.name"]

      assert SortBuilder.convert_sort_field({[:author, :profile, :name], :desc}, sortable_attrs) ==
               "author.profile.name:desc"
    end

    test "filters out unsortable field path list" do
      sortable_attrs = ["title", "artist"]

      assert SortBuilder.convert_sort_field({[:author, :profile, :name], :desc}, sortable_attrs) ==
               nil
    end

    test "converts nested relationship with field list when sortable" do
      sortable_attrs = ["author.company.name"]

      assert SortBuilder.convert_sort_field({{[:author, :company], :name}, :asc}, sortable_attrs) ==
               "author.company.name:asc"
    end

    test "handles calculation sort from actual resource" do
      # Sort by the title_length calculation
      query =
        Album
        |> Ash.Query.load(:title_length)
        |> Ash.Query.sort(title_length: :desc)

      # Extract the sort specification - this will be an Ash.Query.Calculation struct
      [sort_spec] = query.sort

      sortable_attrs = ["title", "artist", "year", "inserted_at", "title_length"]
      result = SortBuilder.convert_sort_field(sort_spec, sortable_attrs)

      assert result == "title_length:desc"
    end

    test "handles aggregate sort from actual resource" do
      # Sort by the track_count aggregate
      query =
        Album
        |> Ash.Query.load(:track_count)
        |> Ash.Query.sort(track_count: :asc)

      # Extract the sort specification - this will be an Ash.Query.Aggregate struct
      [sort_spec] = query.sort

      sortable_attrs = ["title", "artist", "year", "inserted_at", "title_length", "track_count"]
      result = SortBuilder.convert_sort_field(sort_spec, sortable_attrs)

      assert result == "track_count:asc"
    end

    test "converts Ash extended sort directions to basic ones" do
      sortable_attrs = ["title", "artist", "year"]

      assert SortBuilder.convert_sort_field({:title, :desc_nils_last}, sortable_attrs) ==
               "title:desc"

      assert SortBuilder.convert_sort_field({:artist, :asc_nils_first}, sortable_attrs) ==
               "artist:asc"

      assert SortBuilder.convert_sort_field({:year, :desc_nils_first}, sortable_attrs) ==
               "year:desc"

      assert SortBuilder.convert_sort_field({:artist, :asc_nils_last}, sortable_attrs) ==
               "artist:asc"
    end

    test "handles unknown sort specifications" do
      sortable_attrs = ["title", "artist"]
      assert SortBuilder.convert_sort_field({%{unknown: :spec}, :asc}, sortable_attrs) == nil
    end
  end
end
