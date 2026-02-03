defmodule AshMeilisearch.Info do
  @moduledoc """
  Introspection functions for AshMeilisearch configuration.

  Provides functions to query Meilisearch configuration from resources at runtime.
  """

  # Manual implementation of Info functions to avoid Spark.InfoGenerator issues
  def meilisearch_index(resource) do
    Spark.Dsl.Extension.get_opt(resource, [:meilisearch], :index, nil)
  end

  def meilisearch_action_name(resource) do
    Spark.Dsl.Extension.get_opt(resource, [:meilisearch], :action_name, :search)
  end

  def meilisearch_primary_key(resource) do
    # Get the actual primary key from the resource
    # ValidateSearchConfig ensures this is a single field
    case Ash.Resource.Info.primary_key(resource) do
      [key] ->
        key

      _ ->
        # This should not happen after validation, but provide fallback
        :id
    end
  end

  def meilisearch_searchable_attributes(resource) do
    Spark.Dsl.Extension.get_opt(resource, [:meilisearch], :searchable_attributes, [])
  end

  def meilisearch_filterable_attributes(resource) do
    Spark.Dsl.Extension.get_opt(resource, [:meilisearch], :filterable_attributes, [])
  end

  def meilisearch_sortable_attributes(resource) do
    Spark.Dsl.Extension.get_opt(resource, [:meilisearch], :sortable_attributes, [])
  end

  def meilisearch_ranking_rules(resource) do
    Spark.Dsl.Extension.get_opt(resource, [:meilisearch], :ranking_rules, [])
  end

  def meilisearch_stop_words(resource) do
    Spark.Dsl.Extension.get_opt(resource, [:meilisearch], :stop_words, [])
  end

  def meilisearch_synonyms(resource) do
    Spark.Dsl.Extension.get_opt(resource, [:meilisearch], :synonyms, %{})
  end

  def meilisearch_typo_tolerance(resource) do
    Spark.Dsl.Extension.get_opt(resource, [:meilisearch], :typo_tolerance, %{})
  end

  @doc """
  Get searchable attributes from a resource based on meilisearch configuration.

  Returns attributes listed in `searchable_attributes` configuration, converting 
  relationship specs to just the relationship name.
  """
  def searchable_attributes(resource) do
    resource
    |> meilisearch_searchable_attributes()
    |> Enum.flat_map(&field_spec_to_string/1)
  end

  @doc """
  Get filterable attributes from a resource based on meilisearch configuration.

  Returns attributes listed in `filterable_attributes` configuration, converting
  relationship specs to just the relationship name.
  """
  def filterable_attributes(resource) do
    resource
    |> meilisearch_filterable_attributes()
    |> Enum.flat_map(&field_spec_to_string/1)
  end

  @doc """
  Get sortable attributes from a resource based on meilisearch configuration.

  Returns attributes listed in `sortable_attributes` configuration, converting
  relationship specs to just the relationship name.
  """
  def sortable_attributes(resource) do
    resource
    |> meilisearch_sortable_attributes()
    |> Enum.flat_map(&field_spec_to_string/1)
  end

  # Convert field spec to list of strings for Meilisearch settings
  defp field_spec_to_string(field_spec) when is_atom(field_spec) do
    [to_string(field_spec)]
  end

  defp field_spec_to_string({relationship_name, related_fields})
       when is_atom(relationship_name) and is_list(related_fields) do
    # Flatten relationship fields with dot notation: tracks: [:title, :filename] -> ["tracks.title", "tracks.filename"]
    Enum.map(related_fields, fn field -> "#{relationship_name}.#{field}" end)
  end

  defp field_spec_to_string(other) do
    [to_string(other)]
  end

  @doc """
  Get all fields configured for Meilisearch from a resource.

  Returns a list of {name, type, meilisearch_opts} tuples for all attributes
  that are configured in any of the meilisearch lists.
  """
  def get_meilisearch_fields(resource) do
    searchable = meilisearch_searchable_attributes(resource)
    filterable = meilisearch_filterable_attributes(resource)
    sortable = meilisearch_sortable_attributes(resource)

    # Get all unique attributes from all lists
    all_attributes =
      (searchable ++ filterable ++ sortable)
      |> Enum.uniq()

    # Map each attribute to the expected tuple format
    Enum.map(all_attributes, fn attr_name ->
      opts = []
      opts = if attr_name in searchable, do: [{:searchable, true} | opts], else: opts
      opts = if attr_name in filterable, do: [{:filterable, true} | opts], else: opts
      opts = if attr_name in sortable, do: [{:sortable, true} | opts], else: opts

      {attr_name, :attribute, opts}
    end)
  end

  @doc """
  Check if a resource has Meilisearch configured.
  """
  def meilisearch_configured?(resource) do
    # Use Spark.Dsl.Extension.get_opt to check if meilisearch config exists
    case Spark.Dsl.Extension.get_opt(resource, [:meilisearch], :index, nil) do
      nil -> false
      _ -> true
    end
  end
end
