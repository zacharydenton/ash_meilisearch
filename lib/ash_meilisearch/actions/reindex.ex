defmodule AshMeilisearch.Actions.Reindex do
  @moduledoc """
  Manual action to reindex specific records in Meilisearch.

  This action:
  1. Generates search documents for the provided records
  2. Updates those documents in the Meilisearch index
  """

  use Ash.Resource.ManualUpdate
  require Logger
  require Ash.Expr
  require Ash.Query

  @impl true
  def update(changeset, _opts, _context) do
    resource = changeset.resource

    case AshMeilisearch.index_name(resource) do
      nil ->
        {:error, "No Meilisearch index configured for #{inspect(resource)}"}

      index_name ->
        perform_reindex(changeset, resource, index_name)
    end
  end

  defp perform_reindex(changeset, resource, index_name) do
    record = changeset.data
    Logger.info("AshMeilisearch: Starting reindex for record #{record.id} in #{index_name}")

    with {:ok, document} <- generate_record_document(resource, record),
         {:ok, _} <- update_record_in_index(index_name, document) do
      Logger.info("AshMeilisearch: Reindex completed for record #{record.id}")

      {:ok, record}
    else
      {:error, reason} ->
        Logger.error("AshMeilisearch: Reindex failed for record #{record.id}: #{inspect(reason)}")
        {:error, "Reindex failed: #{inspect(reason)}"}
    end
  end

  defp generate_record_document(resource, record) do
    # Load the record with search_document calculation
    case resource
         |> Ash.Query.filter(Ash.Expr.expr(id == ^record.id))
         |> Ash.Query.load(:search_document)
         |> Ash.read_one() do
      {:ok, loaded_record} when not is_nil(loaded_record) ->
        {:ok, loaded_record.search_document}

      {:ok, nil} ->
        {:error, "Record not found: #{record.id}"}

      {:error, error} ->
        {:error, "Failed to load record: #{inspect(error)}"}
    end
  end

  defp update_record_in_index(index_name, document) do
    case AshMeilisearch.Client.index_documents(index_name, [document]) do
      {:ok, _} -> {:ok, :completed}
      error -> error
    end
  end
end
