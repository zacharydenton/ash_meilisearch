defmodule AshMeilisearch.IndexManager do
  @moduledoc """
  Manages Meilisearch index lifecycle including creation, validation, and updates.

  Handles environment-specific behavior:
  - prod: Strict validation, errors if settings don't match
  - dev/test: Auto-create and auto-update index settings
  """

  require Logger

  alias AshMeilisearch.{Config, Client}

  @doc """
  Ensure an index exists and has the correct settings for a resource.

  This is called during resource validation to set up indexes.
  """
  def ensure_index(resource) do
    index_name = get_index_name(resource)
    settings = build_index_settings(resource)

    case get_or_create_index(index_name, settings) do
      {:ok, :created} ->
        Logger.info("AshMeilisearch: Created index '#{index_name}'")
        :ok

      {:ok, :exists} ->
        validate_index_settings!(resource, index_name, settings)

      {:error, reason} ->
        raise "AshMeilisearch: Failed to ensure index '#{index_name}': #{inspect(reason)}"
    end
  end

  @doc """
  Get the full index name for a resource including environment suffix.
  """
  def get_index_name(resource) do
    AshMeilisearch.index_name(resource)
  end

  @doc """
  Build Meilisearch index settings from resource configuration.

  Returns a map with searchableAttributes, filterableAttributes, sortableAttributes, etc.
  """
  def build_index_settings(resource) do
    %{
      searchableAttributes: AshMeilisearch.Info.searchable_attributes(resource),
      filterableAttributes: AshMeilisearch.Info.filterable_attributes(resource),
      sortableAttributes: AshMeilisearch.Info.sortable_attributes(resource),
      rankingRules: AshMeilisearch.Info.meilisearch_ranking_rules(resource),
      stopWords: AshMeilisearch.Info.meilisearch_stop_words(resource),
      synonyms: AshMeilisearch.Info.meilisearch_synonyms(resource),
      primaryKey: AshMeilisearch.primary_key(resource)
    }
    |> Enum.reject(fn
      {_k, v} when is_list(v) -> v == []
      {_k, v} when is_map(v) -> v == %{}
      {_k, v} -> is_nil(v)
    end)
    |> Map.new()
  end

  @doc """
  Delete a test index for cleanup.

  Only works in test environment for indexes with test suffixes.
  """
  def delete_test_index!(resource) do
    case Config.environment() do
      :test ->
        index_name = get_index_name(resource)

        if String.contains?(index_name, Config.test_suffix() || "") do
          case Client.delete_index(index_name) do
            {:ok, _} ->
              :ok

            {:error, reason} ->
              Logger.warning(
                "AshMeilisearch: Failed to delete test index '#{index_name}': #{inspect(reason)}"
              )

              # Don't fail cleanup
              :ok
          end
        else
          Logger.warning(
            "AshMeilisearch: Attempted to delete non-test index '#{index_name}' in test environment"
          )

          :ok
        end

      _ ->
        Logger.warning("AshMeilisearch: delete_test_index!/1 called outside test environment")
        :ok
    end
  end

  # Private functions

  defp get_or_create_index(index_name, settings) do
    case Client.get_index(index_name) do
      {:ok, _index} ->
        {:ok, :exists}

      {:error, %{"code" => "index_not_found"}} ->
        create_index(index_name, settings)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_index(index_name, settings) do
    # Create index with primary key
    primary_key = settings[:primaryKey] || "id"

    case Client.create_index(index_name, %{primaryKey: primary_key}) do
      {:ok, _task} ->
        # Update settings after creation
        update_index_settings(index_name, Map.delete(settings, :primaryKey))
        {:ok, :created}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_index_settings!(resource, index_name, expected_settings) do
    case Client.get_index_settings(index_name) do
      {:ok, current_settings} ->
        case Config.environment() do
          :prod ->
            validate_settings_strict!(resource, index_name, current_settings, expected_settings)

          _ ->
            validate_settings_lenient!(resource, index_name, current_settings, expected_settings)
        end

      {:error, reason} ->
        raise "AshMeilisearch: Failed to get settings for index '#{index_name}': #{inspect(reason)}"
    end
  end

  defp validate_settings_strict!(_resource, index_name, current, expected) do
    mismatches = find_setting_mismatches(current, expected)

    unless Enum.empty?(mismatches) do
      Logger.warning(
        "AshMeilisearch: Index '#{index_name}' settings mismatch, updating: #{inspect(Keyword.keys(mismatches))}"
      )

      update_index_settings(index_name, expected)
    end

    :ok
  end

  defp validate_settings_lenient!(resource, index_name, current, expected) do
    mismatches = find_setting_mismatches(current, expected)

    if Enum.empty?(mismatches) do
      :ok
    else
      # Only log if this looks like a meaningful change (not just initial setup)
      is_initial_setup = is_initial_index_setup?(current)

      if is_initial_setup do
        Logger.debug(
          "AshMeilisearch: Configuring new index '#{index_name}' for #{inspect(resource)}"
        )
      else
        Logger.info(
          "AshMeilisearch: Updating index '#{index_name}' settings to match #{inspect(resource)} configuration"
        )
      end

      update_index_settings(index_name, expected)
    end
  end

  # Check if this appears to be initial setup (index has default/empty settings)
  defp is_initial_index_setup?(current_settings) do
    searchable =
      Map.get(current_settings, "searchableAttributes") ||
        Map.get(current_settings, :searchableAttributes)

    filterable =
      Map.get(current_settings, "filterableAttributes") ||
        Map.get(current_settings, :filterableAttributes)

    sortable =
      Map.get(current_settings, "sortableAttributes") ||
        Map.get(current_settings, :sortableAttributes)

    # Consider it initial setup if we have default searchable ["*"] and empty filterable/sortable
    searchable == ["*"] && filterable == [] && sortable == []
  end

  defp find_setting_mismatches(current, expected) do
    expected
    # Skip primaryKey - it's set at creation, not via settings
    |> Enum.reject(fn {key, _value} -> key == :primaryKey end)
    |> Enum.reduce([], fn {key, expected_value}, mismatches ->
      current_value = Map.get(current, Atom.to_string(key)) || Map.get(current, key)

      # Normalize for comparison (convert strings to atoms in lists, handle ordering)
      normalized_current = normalize_setting_value(current_value)
      normalized_expected = normalize_setting_value(expected_value)

      # Handle special cases where defaults should be considered "unset"
      equivalent = settings_equivalent?(key, normalized_current, normalized_expected)

      if equivalent do
        mismatches
      else
        [{key, expected_value, current_value} | mismatches]
      end
    end)
  end

  # Check if two setting values should be considered equivalent
  defp settings_equivalent?(_key, current, expected) when current == expected, do: true

  # Handle primaryKey: nil current vs expected value means it needs to be set
  defp settings_equivalent?(:primaryKey, nil, _expected), do: false

  # Handle empty arrays vs configured arrays - these are real differences
  defp settings_equivalent?(_key, [], expected) when is_list(expected), do: false

  # Handle ["*"] searchableAttributes default vs configured attributes
  defp settings_equivalent?(:searchableAttributes, ["*"], expected) when is_list(expected),
    do: false

  defp settings_equivalent?(_key, _current, _expected), do: false

  defp normalize_setting_value(value) when is_list(value) do
    value
    |> Enum.map(&to_string/1)
    |> Enum.sort()
  end

  defp normalize_setting_value(value) when is_binary(value), do: value
  defp normalize_setting_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_setting_value(nil), do: nil
  defp normalize_setting_value(value), do: value

  defp update_index_settings(index_name, settings) do
    # Remove primaryKey from settings update (it's set during index creation)
    settings_to_update = Map.delete(settings, :primaryKey)

    case Client.update_index_settings(index_name, settings_to_update) do
      {:ok, _task} ->
        :ok

      {:error, reason} ->
        Logger.error(
          "AshMeilisearch: Failed to update settings for #{index_name}: #{inspect(reason)}"
        )

        raise "AshMeilisearch: Failed to update settings for index '#{index_name}': #{inspect(reason)}"
    end
  end
end
