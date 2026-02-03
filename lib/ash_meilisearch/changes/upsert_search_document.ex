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
    records = List.wrap(result)
    resource = changeset.resource

    # Build documents synchronously (needs record data from the transaction)
    search_documents =
      records
      |> Enum.map(&build_search_document(resource, &1))
      |> Enum.reject(&is_nil/1)

    # Send to Meilisearch asynchronously so we don't block the action
    if search_documents != [] do
      index_name = AshMeilisearch.index_name(resource)

      Task.start(fn ->
        case AshMeilisearch.Client.add_documents(index_name, search_documents) do
          {:ok, _task} ->
            :ok

          {:error, reason} ->
            Logger.error(
              "AshMeilisearch: Failed to add documents to '#{index_name}': #{inspect(reason)}"
            )
        end
      end)
    end

    {:ok, result}
  end

  defp build_search_document(resource, record) do
    meilisearch_fields = AshMeilisearch.Info.get_meilisearch_fields(resource)
    primary_key = AshMeilisearch.primary_key(resource)

    # Load any relationships needed for the search document
    relationship_loads =
      meilisearch_fields
      |> Enum.flat_map(fn
        {{rel_name, related_fields}, :relationship, _opts} -> [{rel_name, related_fields}]
        _ -> []
      end)

    record =
      if relationship_loads != [] do
        Ash.load!(record, relationship_loads)
      else
        record
      end

    AshMeilisearch.Calculations.SearchDocument.format_document(
      record,
      meilisearch_fields,
      primary_key
    )
  end
end
