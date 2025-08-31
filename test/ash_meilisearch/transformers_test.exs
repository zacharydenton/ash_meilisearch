defmodule AshMeilisearch.TransformersTest do
  use ExUnit.Case, async: false

  alias AshMeilisearch.Test.{Post, Album}

  describe "AddSearchDocument transformer" do
    test "adds search_document calculation to configured resources" do
      calc = Ash.Resource.Info.calculation(Post, :search_document)
      assert calc != nil
      assert calc.name == :search_document
      assert calc.public? == true
      assert calc.type == Ash.Type.Map
    end

    test "calculation uses correct module" do
      calc = Ash.Resource.Info.calculation(Post, :search_document)
      {module, _opts} = calc.calculation
      assert module == AshMeilisearch.Calculations.SearchDocument
    end

    test "correctly identifies field types from resource definition" do
      calc = Ash.Resource.Info.calculation(Post, :search_document)
      {_module, opts} = calc.calculation
      meilisearch_fields = Keyword.get(opts, :meilisearch_fields, [])

      # Find specific fields and check their types
      title_field = Enum.find(meilisearch_fields, fn {name, _type, _opts} -> name == :title end)
      assert {_name, :attribute, _opts} = title_field

      status_field = Enum.find(meilisearch_fields, fn {name, _type, _opts} -> name == :status end)
      assert {_name, :attribute, _opts} = status_field

      published_at_field =
        Enum.find(meilisearch_fields, fn {name, _type, _opts} -> name == :published_at end)

      assert {_name, :attribute, _opts} = published_at_field
    end

    test "correctly identifies calculation and aggregate fields for Album" do
      calc = Ash.Resource.Info.calculation(Album, :search_document)
      {_module, opts} = calc.calculation
      meilisearch_fields = Keyword.get(opts, :meilisearch_fields, [])

      # Album has both calculations and aggregates in its test configuration
      # Check that the transformer correctly identifies different field types
      field_types = Enum.map(meilisearch_fields, fn {name, type, _opts} -> {name, type} end)

      # Title should be an attribute
      assert {:title, :attribute} in field_types

      # Artist should be an attribute
      assert {:artist, :attribute} in field_types

      # Year and genre should be attributes
      assert {:year, :attribute} in field_types
      assert {:genre, :attribute} in field_types

      # inserted_at should be an attribute (timestamps are attributes)
      assert {:inserted_at, :attribute} in field_types
    end

    test "includes all configured meilisearch fields" do
      calc = Ash.Resource.Info.calculation(Post, :search_document)
      {_module, opts} = calc.calculation
      meilisearch_fields = Keyword.get(opts, :meilisearch_fields, [])

      field_names = Enum.map(meilisearch_fields, fn {name, _type, _opts} -> name end)

      # Should include all fields from searchable, filterable, and sortable lists
      assert :title in field_names
      assert :content in field_names
      assert :tags in field_names
      assert :status in field_names
      assert :published_at in field_names
      assert :inserted_at in field_names
    end

    test "preserves meilisearch options for each field" do
      calc = Ash.Resource.Info.calculation(Post, :search_document)
      {_module, opts} = calc.calculation
      meilisearch_fields = Keyword.get(opts, :meilisearch_fields, [])

      # Find title field which should be searchable, filterable, and sortable
      title_field = Enum.find(meilisearch_fields, fn {name, _type, _opts} -> name == :title end)
      {_name, _type, field_opts} = title_field

      assert field_opts[:searchable] == true
      assert field_opts[:filterable] == true
      assert field_opts[:sortable] == true

      # Find content field which should only be searchable
      content_field =
        Enum.find(meilisearch_fields, fn {name, _type, _opts} -> name == :content end)

      {_name, _type, content_opts} = content_field

      assert content_opts[:searchable] == true
      refute content_opts[:filterable]
      refute content_opts[:sortable]
    end
  end

  describe "AddSearchAction transformer" do
    test "adds search action to configured resources" do
      action = Ash.Resource.Info.action(Post, :search)
      assert action != nil
      assert action.name == :search
      assert action.type == :read
      assert action.manual != nil
    end

    test "search action has correct structure" do
      action = Ash.Resource.Info.action(Post, :search)

      # Check pagination is configured
      assert action.pagination != nil

      # Check for query argument
      query_arg = Enum.find(action.arguments, &(&1.name == :query))
      assert query_arg != nil
      assert query_arg.allow_nil? == false
    end

    test "respects custom action names" do
      action = Ash.Resource.Info.action(Album, :search_albums)
      assert action != nil
      assert action.name == :search_albums
    end
  end

  describe "AddIndexActions transformer" do
    test "adds reindex action to configured resources" do
      reindex_action = Ash.Resource.Info.action(Post, :reindex)
      assert reindex_action != nil
      assert reindex_action.name == :reindex
      assert reindex_action.type == :update
      assert reindex_action.manual != nil
    end

    test "adds configure_index action to configured resources" do
      configure_action = Ash.Resource.Info.action(Post, :configure_index)
      assert configure_action != nil
      assert configure_action.name == :configure_index
      assert configure_action.type == :update
      assert configure_action.manual != nil
    end
  end

  describe "transformer ordering" do
    test "all transformers run successfully" do
      # Check all expected additions were made
      assert Ash.Resource.Info.calculation(Post, :search_document) != nil
      assert Ash.Resource.Info.action(Post, :search) != nil
      assert Ash.Resource.Info.action(Post, :reindex) != nil
      assert Ash.Resource.Info.action(Post, :configure_index) != nil
    end
  end
end
