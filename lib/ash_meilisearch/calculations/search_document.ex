defmodule AshMeilisearch.Calculations.SearchDocument do
  @moduledoc """
  Auto-generated calculation that returns a resource formatted as a Meilisearch document.

  This calculation is automatically added to resources with Meilisearch configuration.
  It includes all attributes, calculations, and aggregates marked for search indexing.
  """

  use Ash.Resource.Calculation
  require Logger

  @impl true
  def load(_query, opts, _context) do
    meilisearch_fields = Keyword.get(opts, :meilisearch_fields, [])

    # Extract loads needed for the configured fields
    loads = extract_loads(meilisearch_fields)

    loads
  end

  @impl true
  def calculate(records, opts, _context) when is_list(records) do
    meilisearch_fields = Keyword.get(opts, :meilisearch_fields, [])
    primary_key_field = Keyword.get(opts, :primary_key_field, :id)

    documents = Enum.map(records, &format_document(&1, meilisearch_fields, primary_key_field))
    {:ok, documents}
  end

  defp extract_loads(meilisearch_fields) do
    # Extract all fields that need to be loaded
    meilisearch_fields
    |> Enum.flat_map(fn
      # Simple fields that need loading (calculations and aggregates)
      {field_name, field_type, _opts} when field_type in [:calculation, :aggregate] ->
        [field_name]

      # Relationship fields with specific attributes to load  
      {{relationship_name, related_fields}, :relationship, _opts} ->
        [{relationship_name, related_fields}]

      # Skip other fields (attributes don't need explicit loading)
      _ ->
        []
    end)
  end

  def format_document(record, meilisearch_fields, primary_key_field \\ :id) do
    # Start with basic document structure using the actual primary key
    base_document = %{
      to_string(primary_key_field) => Map.get(record, primary_key_field)
    }

    # Add configured fields to the document
    Enum.reduce(meilisearch_fields, base_document, fn field_spec, doc ->
      case field_spec do
        # Simple fields (attributes, calculations, aggregates)
        {field_name, field_type, _opts} when field_type in [:attribute, :calculation, :aggregate] ->
          case get_field_value(record, field_name, field_type) do
            {:ok, value} ->
              Map.put(doc, to_string(field_name), value)

            {:error, _reason} ->
              doc
          end

        # Relationship fields
        {{relationship_name, related_fields}, :relationship, _opts} ->
          case get_relationship_value(record, relationship_name, related_fields) do
            {:ok, value} ->
              Map.put(doc, to_string(relationship_name), value)

            {:error, _reason} ->
              doc
          end

        # Skip unknown field types
        _ ->
          doc
      end
    end)
  end

  def get_field_value(record, field_name, field_type)
      when field_type in [:attribute, :calculation, :aggregate] do
    case Map.get(record, field_name, :missing) do
      :missing -> {:error, :missing}
      %Ash.NotLoaded{} -> {:error, :not_loaded}
      value -> {:ok, convert_value_for_meilisearch(value)}
    end
  end

  def get_relationship_value(record, relationship_name, related_fields) do
    case Map.get(record, relationship_name, :missing) do
      :missing ->
        {:error, :missing}

      %Ash.NotLoaded{} ->
        {:error, :not_loaded}

      nil ->
        {:ok, nil}

      # Single relationship (belongs_to, has_one) 
      related_record when is_struct(related_record) ->
        {:ok, format_related_record(related_record, related_fields)}

      # Multiple relationships (has_many, many_to_many)
      related_records when is_list(related_records) ->
        formatted_records =
          related_records
          |> Enum.map(&format_related_record(&1, related_fields))
          |> Enum.reject(&is_nil/1)

        {:ok, formatted_records}

      _ ->
        {:error, :invalid_relationship_data}
    end
  end

  defp format_related_record(record, related_fields) do
    # Handle NotLoaded records
    if match?(%Ash.NotLoaded{}, record) do
      nil
    else
      # Create object with specified fields: {name: "Foo", id: "123"}
      Enum.reduce(related_fields, %{}, fn field_name, acc ->
        case Map.get(record, field_name, :missing) do
          :missing -> acc
          %Ash.NotLoaded{} -> acc
          value -> Map.put(acc, field_name, convert_value_for_meilisearch(value))
        end
      end)
    end
  end

  # Keep booleans as-is
  defp convert_value_for_meilisearch(bool) when is_boolean(bool) do
    bool
  end

  # Convert non-boolean atoms to strings
  defp convert_value_for_meilisearch(atom) when is_atom(atom) and not is_nil(atom) do
    Atom.to_string(atom)
  end

  # Convert DateTime to unix timestamp (integer seconds)
  defp convert_value_for_meilisearch(%DateTime{} = dt) do
    DateTime.to_unix(dt)
  end

  # Convert Date to ISO 8601 date string "yyyy-mm-dd"
  defp convert_value_for_meilisearch(%Date{} = date) do
    Date.to_iso8601(date)
  end

  # Convert NaiveDateTime to unix timestamp (assume UTC)
  defp convert_value_for_meilisearch(%NaiveDateTime{} = ndt) do
    ndt
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_unix()
  end

  # Keep other types as-is (strings, integers, floats, booleans, nil)
  defp convert_value_for_meilisearch(other) do
    other
  end
end
