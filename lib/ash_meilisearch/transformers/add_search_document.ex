defmodule AshMeilisearch.Transformers.AddSearchDocument do
  @moduledoc """
  Adds a search_document calculation to resources with Meilisearch configuration.

  The calculation auto-generates Meilisearch documents based on attributes,
  calculations, and aggregates marked with `meilisearch` options.
  """

  use Spark.Dsl.Transformer

  def after?(AshMeilisearch.Transformers.ValidateSearchConfig), do: true
  def after?(_), do: false

  def transform(dsl_state) do
    # Access meilisearch config from DSL state map structure
    meilisearch_config = get_in(dsl_state, [Access.key([:meilisearch]), Access.key(:opts)])

    case meilisearch_config do
      config when is_list(config) and length(config) > 0 ->
        # Check if index is configured
        if Keyword.has_key?(config, :index) do
          meilisearch_fields = extract_meilisearch_fields(meilisearch_config, dsl_state)

          case meilisearch_fields do
            [] ->
              # No fields configured for search, skip adding calculation
              {:ok, dsl_state}

            fields ->
              add_search_document_calculation(dsl_state, fields)
          end
        else
          {:ok, dsl_state}
        end

      _ ->
        {:ok, dsl_state}
    end
  end

  defp extract_meilisearch_fields(meilisearch_config, dsl_state) do
    # Extract fields from the meilisearch configuration lists (config is a keyword list)
    searchable = Keyword.get(meilisearch_config, :searchable_attributes, [])
    filterable = Keyword.get(meilisearch_config, :filterable_attributes, [])
    sortable = Keyword.get(meilisearch_config, :sortable_attributes, [])

    # Get all unique field specifications from all lists  
    all_field_specs = (searchable ++ filterable ++ sortable) |> Enum.uniq()

    # Get resource info from DSL state
    attributes = get_in(dsl_state, [Access.key([:attributes]), Access.key(:entities)]) || []
    calculations = get_in(dsl_state, [Access.key([:calculations]), Access.key(:entities)]) || []
    aggregates = get_in(dsl_state, [Access.key([:aggregates]), Access.key(:entities)]) || []
    relationships = get_in(dsl_state, [Access.key([:relationships]), Access.key(:entities)]) || []

    # Create lookup maps for efficient field type detection
    attribute_names = MapSet.new(attributes, & &1.name)
    calculation_names = MapSet.new(calculations, & &1.name)
    aggregate_names = MapSet.new(aggregates, & &1.name)
    relationship_names = MapSet.new(relationships, & &1.name)

    # Parse and map each field specification
    Enum.map(all_field_specs, fn field_spec ->
      parse_field_spec(field_spec, {
        searchable,
        filterable,
        sortable,
        attribute_names,
        calculation_names,
        aggregate_names,
        relationship_names
      })
    end)
  end

  defp parse_field_spec(
         field_name,
         {searchable, filterable, sortable, attribute_names, calculation_names, aggregate_names,
          _relationship_names}
       )
       when is_atom(field_name) do
    # Simple field: :title, :details, etc.
    opts = []
    opts = if field_name in searchable, do: [{:searchable, true} | opts], else: opts
    opts = if field_name in filterable, do: [{:filterable, true} | opts], else: opts
    opts = if field_name in sortable, do: [{:sortable, true} | opts], else: opts

    # Determine field type based on resource definition
    field_type =
      cond do
        MapSet.member?(attribute_names, field_name) -> :attribute
        MapSet.member?(calculation_names, field_name) -> :calculation
        MapSet.member?(aggregate_names, field_name) -> :aggregate
        # Fallback to attribute
        true -> :attribute
      end

    {field_name, field_type, opts}
  end

  defp parse_field_spec(
         {relationship_name, related_fields},
         {searchable, filterable, sortable, _attribute_names, _calculation_names,
          _aggregate_names, relationship_names}
       )
       when is_atom(relationship_name) and is_list(related_fields) do
    # Relationship field: tags: [:name], studio: [:name, :id], etc.
    field_spec = {relationship_name, related_fields}

    opts = []
    opts = if field_spec in searchable, do: [{:searchable, true} | opts], else: opts
    opts = if field_spec in filterable, do: [{:filterable, true} | opts], else: opts
    opts = if field_spec in sortable, do: [{:sortable, true} | opts], else: opts

    # Verify the relationship exists
    field_type =
      if MapSet.member?(relationship_names, relationship_name), do: :relationship, else: :unknown

    {{relationship_name, related_fields}, field_type, opts}
  end

  defp parse_field_spec(unknown_spec, _) do
    # Handle unknown field specifications gracefully
    {unknown_spec, :unknown, []}
  end

  defp get_primary_key_field(dsl_state) do
    # Get attributes that are marked as primary key
    attributes = get_in(dsl_state, [Access.key([:attributes]), Access.key(:entities)]) || []

    primary_key_attrs =
      attributes
      |> Enum.filter(& &1.primary_key?)
      |> Enum.map(& &1.name)

    # ValidateSearchConfig ensures we have exactly one primary key
    # This should always return a single field at this point
    case primary_key_attrs do
      [single] -> single
      # Fallback for safety, but should not happen after validation
      _ -> :id
    end
  end

  defp add_search_document_calculation(dsl_state, meilisearch_fields) do
    # Get the primary key from the resource's attributes
    primary_key = get_primary_key_field(dsl_state)

    calculation_module =
      {AshMeilisearch.Calculations.SearchDocument,
       meilisearch_fields: meilisearch_fields, primary_key_field: primary_key}

    opts = [
      public?: true,
      description: "Auto-generated Meilisearch search document"
    ]

    Ash.Resource.Builder.add_calculation(
      dsl_state,
      :search_document,
      :map,
      calculation_module,
      opts
    )
  end
end
