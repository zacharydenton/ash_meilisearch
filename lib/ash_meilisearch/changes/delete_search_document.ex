defmodule AshMeilisearch.Changes.DeleteSearchDocument do
  @moduledoc """
  After-action change that removes records from Meilisearch after destroy.

  This change is automatically added to destroy actions by the AddCrudHooks transformer.
  """

  use Ash.Resource.Change

  require Logger

  def change(changeset, _opts, _context) do
    # Capture the record before deletion for Meilisearch cleanup
    Ash.Changeset.before_action(changeset, &capture_record_for_deletion/1)
    |> Ash.Changeset.after_action(&delete_search_document/2)
  end

  defp capture_record_for_deletion(changeset) do
    # Store the original record data in changeset context for use after deletion
    case changeset.data do
      %{id: id} = record ->
        Ash.Changeset.put_context(changeset, :meilisearch_delete_id, id)
        |> Ash.Changeset.put_context(:meilisearch_delete_record, record)

      _ ->
        changeset
    end
  end

  defp delete_search_document(changeset, result) do
    resource = changeset.resource

    case Map.get(changeset.context, :meilisearch_delete_id) do
      nil ->
        Logger.warning(
          "AshMeilisearch: No record ID captured for deletion from #{inspect(resource)}"
        )

      record_id ->
        index_name = AshMeilisearch.index_name(resource)

        Task.start(fn ->
          case AshMeilisearch.Client.delete_document(index_name, record_id) do
            {:ok, _task} ->
              :ok

            {:error, reason} ->
              Logger.error(
                "AshMeilisearch: Failed to delete document #{record_id} from '#{index_name}': #{inspect(reason)}"
              )
          end
        end)
    end

    {:ok, result}
  end
end
