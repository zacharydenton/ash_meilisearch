defmodule AshMeilisearch.Changes.UpsertSearchDocument do
  @moduledoc """
  After-action change that synchronizes records with Meilisearch after create/update.

  This change is automatically added to create/update actions by the AddCrudHooks transformer.
  """

  use Ash.Resource.Change

  require Logger

  def change(changeset, _opts, _context) do
    # The change runs after the action, so we get the result via after_action
    Ash.Changeset.after_action(changeset, &upsert_search_document/2)
  end

  defp upsert_search_document(changeset, result) do
    # Handle both single records and lists of records
    records = List.wrap(result)
    resource = changeset.resource

    case upsert_documents(resource, records) do
      {:ok, _} ->
        {:ok, result}

      {:error, error} ->
        # Log error but don't fail the database transaction
        Logger.error(
          "AshMeilisearch: Failed to upsert search documents for #{inspect(resource)}: #{inspect(error)}"
        )

        {:ok, result}
    end
  end

  defp upsert_documents(resource, records) when is_list(records) do
    search_documents =
      records
      |> Enum.map(&build_search_document(resource, &1))
      |> Enum.reject(&is_nil/1)

    case search_documents do
      [] ->
        {:ok, :no_documents}

      documents ->
        index_name = AshMeilisearch.index_name(resource)

        case AshMeilisearch.Client.add_documents(index_name, documents) do
          {:ok, task} ->
            {:ok, task}

          {:error, reason} ->
            Logger.error(
              "AshMeilisearch: Failed to add documents to '#{index_name}': #{inspect(reason)}"
            )

            {:error, reason}
        end
    end
  end

  defp build_search_document(resource, record) do
    # Get the meilisearch fields configuration for this resource
    meilisearch_fields = AshMeilisearch.Info.get_meilisearch_fields(resource)
    primary_key = AshMeilisearch.primary_key(resource)

    AshMeilisearch.Calculations.SearchDocument.format_document(
      record,
      meilisearch_fields,
      primary_key
    )
  end
end
