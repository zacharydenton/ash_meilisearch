defmodule AshMeilisearch.Actions.ConfigureIndex do
  @moduledoc """
  Manual action to configure Meilisearch index settings based on resource configuration.

  This action updates the Meilisearch index settings to match the searchable,
  filterable, and sortable attributes defined in the resource.
  """

  use Ash.Resource.ManualUpdate
  require Logger

  @impl true
  def update(changeset, _opts, _context) do
    resource = changeset.resource

    case AshMeilisearch.index_name(resource) do
      nil ->
        {:error, "No Meilisearch index configured for #{inspect(resource)}"}

      index_name ->
        perform_configuration(changeset, resource, index_name)
    end
  end

  defp perform_configuration(changeset, resource, index_name) do
    Logger.info("AshMeilisearch: Configuring index #{index_name} for #{inspect(resource)}")

    with {:ok, _} <- ensure_index_exists(index_name),
         {:ok, _} <- update_searchable_attributes(resource, index_name),
         {:ok, _} <- update_filterable_attributes(resource, index_name),
         {:ok, _} <- update_sortable_attributes(resource, index_name) do
      Logger.info("AshMeilisearch: Index configuration completed for #{index_name}")
      {:ok, changeset.data}
    else
      {:error, reason} ->
        Logger.error(
          "AshMeilisearch: Index configuration failed for #{index_name}: #{inspect(reason)}"
        )

        {:error, "Index configuration failed: #{inspect(reason)}"}
    end
  end

  defp ensure_index_exists(index_name) do
    case AshMeilisearch.Client.ensure_index(index_name) do
      :ok -> {:ok, :exists}
      error -> error
    end
  end

  defp update_searchable_attributes(resource, index_name) do
    searchable_attributes = AshMeilisearch.Info.searchable_attributes(resource)

    case searchable_attributes do
      [] ->
        {:ok, :skipped}

      attributes ->
        Logger.info("AshMeilisearch: Setting searchable attributes: #{inspect(attributes)}")
        AshMeilisearch.Client.update_setting(index_name, "searchableAttributes", attributes)
    end
  end

  defp update_filterable_attributes(resource, index_name) do
    filterable_attributes = AshMeilisearch.Info.filterable_attributes(resource)

    case filterable_attributes do
      [] ->
        {:ok, :skipped}

      attributes ->
        Logger.info("AshMeilisearch: Setting filterable attributes: #{inspect(attributes)}")
        AshMeilisearch.Client.update_setting(index_name, "filterableAttributes", attributes)
    end
  end

  defp update_sortable_attributes(resource, index_name) do
    sortable_attributes = AshMeilisearch.Info.sortable_attributes(resource)

    case sortable_attributes do
      [] ->
        {:ok, :skipped}

      attributes ->
        Logger.info("AshMeilisearch: Setting sortable attributes: #{inspect(attributes)}")
        AshMeilisearch.Client.update_setting(index_name, "sortableAttributes", attributes)
    end
  end
end
