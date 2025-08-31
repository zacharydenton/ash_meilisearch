defmodule AshMeilisearch.SortBuilder do
  @moduledoc """
  Converts Ash.Query.sort to Meilisearch sort array.

  Translates Ash sorting syntax into Meilisearch-compatible sort strings.

  ## Examples

      # Single sort
      [title: :asc] -> ["title:asc"]
      
      # Multiple sorts  
      [title: :asc, created_at: :desc] -> ["title:asc", "created_at:desc"]
      
      # Relationship sorts (if supported by index)
      [{:studio, :name}: :asc] -> ["studio.name:asc"]
      
      # Complex field paths
      [{[:studio, :country], :name}: :asc] -> ["studio.country.name:asc"]
  """

  require Logger

  @doc """
  Build Meilisearch sort array from Ash query sort.

  Returns an empty list if no sorts provided.
  """
  def build_sort([], _resource), do: []

  def build_sort(ash_sorts, resource) when is_list(ash_sorts) do
    # Get sortable attributes from resource configuration
    sortable_attrs = get_sortable_attributes(resource)

    sorts =
      ash_sorts
      |> Enum.map(&convert_sort_field(&1, sortable_attrs))
      |> Enum.reject(&is_nil/1)

    sorts
  end

  def build_sort(nil, _resource), do: []

  def convert_sort_field({field, direction}, sortable_attrs) when is_atom(field) do
    build_sort_string(field, direction, sortable_attrs)
  end

  def convert_sort_field({{relationship, field}, direction}, sortable_attrs)
      when is_atom(relationship) and is_atom(field) do
    sort_key = "#{relationship}.#{field}"

    if sort_key in sortable_attrs or "#{relationship}_#{field}" in sortable_attrs do
      build_sort_string(sort_key, direction, sortable_attrs)
    else
      Logger.warning(
        "AshMeilisearch: Skipping unsortable field '#{sort_key}' (not in sortable attributes)"
      )

      nil
    end
  end

  def convert_sort_field({field_path, direction}, sortable_attrs) when is_list(field_path) do
    path = Enum.join(field_path, ".")
    build_sort_string(path, direction, sortable_attrs)
  end

  def convert_sort_field({{relationships, field}, direction}, sortable_attrs)
      when is_list(relationships) and is_atom(field) do
    path = Enum.join(relationships ++ [field], ".")
    build_sort_string(path, direction, sortable_attrs)
  end

  # Handle calculation sort specifications
  def convert_sort_field(
        {%Ash.Query.Calculation{calc_name: calc_name}, direction},
        sortable_attrs
      ) do
    build_sort_string(calc_name, direction, sortable_attrs)
  end

  # Handle aggregate sort specifications
  def convert_sort_field({%Ash.Query.Aggregate{agg_name: agg_name}, direction}, sortable_attrs) do
    build_sort_string(agg_name, direction, sortable_attrs)
  end

  def convert_sort_field(sort_spec, _sortable_attrs) do
    Logger.warning("AshMeilisearch: Unknown sort specification: #{inspect(sort_spec)}")
    # Return nil to indicate this sort should be skipped
    nil
  end

  defp build_sort_string(field, direction, sortable_attrs) do
    field_str = to_string(field)

    if field_str in sortable_attrs do
      meilisearch_direction = normalize_direction(direction, field_str)
      "#{field_str}:#{meilisearch_direction}"
    else
      Logger.warning(
        "AshMeilisearch: Skipping unsortable field '#{field}' (not in sortable attributes)"
      )

      nil
    end
  end

  defp normalize_direction(:desc_nils_last, field_name) do
    Logger.warning(
      "AshMeilisearch: Converting '#{field_name}' sort from 'desc_nils_last' to 'desc' - Meilisearch doesn't support nil ordering. Consider adding a 'not is_nil(#{field_name})' filter."
    )

    :desc
  end

  defp normalize_direction(:asc_nils_first, field_name) do
    Logger.warning(
      "AshMeilisearch: Converting '#{field_name}' sort from 'asc_nils_first' to 'asc' - Meilisearch doesn't support nil ordering. Consider adding a 'is_nil(#{field_name})' filter."
    )

    :asc
  end

  defp normalize_direction(:desc_nils_first, field_name) do
    Logger.warning(
      "AshMeilisearch: Converting '#{field_name}' sort from 'desc_nils_first' to 'desc' - Meilisearch doesn't support nil ordering. Consider adding a 'is_nil(#{field_name})' filter."
    )

    :desc
  end

  defp normalize_direction(:asc_nils_last, field_name) do
    Logger.warning(
      "AshMeilisearch: Converting '#{field_name}' sort from 'asc_nils_last' to 'asc' - Meilisearch doesn't support nil ordering. Consider adding a 'not is_nil(#{field_name})' filter."
    )

    :asc
  end

  defp normalize_direction(direction, _field_name) when direction in [:asc, :desc], do: direction

  defp get_sortable_attributes(resource) do
    case AshMeilisearch.Info.meilisearch_sortable_attributes(resource) do
      nil -> []
      attrs -> Enum.map(attrs, &to_string/1)
    end
  end
end
