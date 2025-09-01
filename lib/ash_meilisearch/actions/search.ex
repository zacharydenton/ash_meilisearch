defmodule AshMeilisearch.Actions.Search do
  @moduledoc """
  Auto-generated manual search implementation using Meilisearch.

  Provides a generic manual read action that translates Ash queries into
  Meilisearch searches, automatically generated for any resource with
  Meilisearch configuration.
  """

  use Ash.Resource.ManualRead
  require Logger
  require Ash.Expr
  require Ash.Query

  @impl true
  def read(ash_query, _ecto_query, _opts, _context) do
    resource = ash_query.resource

    # Get Meilisearch configuration for this resource
    case AshMeilisearch.index_name(resource) do
      nil ->
        {:error, "No Meilisearch index configured for #{inspect(resource)}"}

      index_name ->
        perform_search(ash_query, index_name)
    end
  end

  defp perform_search(ash_query, index_name) do
    query_arg = Map.get(ash_query.arguments, :query)

    # Detect if this is single search (string/ci_string) or multisearch (list)
    case normalize_query_arg(query_arg) do
      {:single, search_query} ->
        perform_single_search(ash_query, index_name, search_query)

      {:multi, queries} ->
        perform_multisearch(ash_query, index_name, queries)
    end
  end

  defp normalize_query_arg(query_arg) do
    case query_arg do
      # Handle Ash union type - extract the actual value
      %Ash.Union{type: :ci_string, value: %Ash.CiString{string: str}} ->
        {:single, str}

      %Ash.Union{type: :ci_string, value: str} when is_binary(str) ->
        {:single, str}

      %Ash.Union{type: :queries, value: queries} when is_list(queries) ->
        {:multi, queries}

      # Default to empty single search
      _ ->
        {:single, ""}
    end
  end

  defp perform_single_search(ash_query, index_name, search_query) do
    # Extract search parameters
    filter_string = build_meilisearch_filter(ash_query)
    sort_array = build_meilisearch_sort(ash_query)

    # Extract pagination
    limit = get_limit(ash_query)
    offset = get_offset(ash_query)

    # Prepare search options
    search_opts = %{
      limit: limit,
      offset: offset,
      attributesToRetrieve: ["id"]
    }

    search_opts =
      if filter_string do
        Map.put(search_opts, :filter, filter_string)
      else
        search_opts
      end

    search_opts =
      if length(sort_array) > 0 do
        Map.put(search_opts, :sort, sort_array)
      else
        search_opts
      end

    search_opts =
      if search_query != "" do
        Map.merge(search_opts, %{
          attributesToHighlight: ["*"],
          showRankingScore: true
        })
      else
        search_opts
      end

    case AshMeilisearch.Client.search(index_name, search_query, search_opts) do
      {:ok, %{"hits" => hits} = response} ->
        process_search_results(ash_query, hits, response)

      {:search_error, error} ->
        Logger.error("AshMeilisearch single search failed: #{inspect(error)}")
        {:error, "Search service error: #{inspect(error)}"}

      {:error, error} ->
        Logger.error("AshMeilisearch single search request failed: #{inspect(error)}")
        {:error, "Search request failed: #{inspect(error)}"}
    end
  end

  defp perform_multisearch(ash_query, index_name, queries) do
    federation_opts = Map.get(ash_query.arguments, :federation, %{})

    # Extract pagination from Ash query for federation
    limit = get_limit(ash_query)
    offset = get_offset(ash_query)

    # Build Meilisearch multisearch queries
    meilisearch_queries =
      Enum.map(queries, fn query_map ->
        # Each query should be a map with at least indexUid and q
        base_query = %{
          indexUid: index_name,
          attributesToRetrieve: ["id"],
          showRankingScore: true
        }

        # Merge user-provided query options
        Map.merge(base_query, query_map)
      end)

    # Build federation options
    federation_options =
      federation_opts
      |> Map.put(:limit, Map.get(federation_opts, :limit, limit))
      |> then(fn opts ->
        if offset > 0 do
          Map.put(opts, :offset, offset)
        else
          opts
        end
      end)

    case AshMeilisearch.Client.multisearch(meilisearch_queries, federation: federation_options) do
      {:ok, %{"hits" => hits} = response} ->
        process_search_results(ash_query, hits, response)

      {:search_error, error} ->
        Logger.error("AshMeilisearch multisearch failed: #{inspect(error)}")
        {:error, "Multisearch service error: #{inspect(error)}"}

      {:error, error} ->
        Logger.error("AshMeilisearch multisearch request failed: #{inspect(error)}")
        {:error, "Multisearch request failed: #{inspect(error)}"}
    end
  end

  defp process_search_results(ash_query, hits, response) do
    # Extract IDs from Meilisearch results
    ids = Enum.map(hits, & &1["id"])

    # Load actual records using IDs, preserving original query loads
    records =
      if length(ids) > 0 do
        ash_query.resource
        |> Ash.Query.new()
        |> Ash.Query.filter(Ash.Expr.expr(id in ^ids))
        |> Ash.Query.load(ash_query.load)
        |> Ash.read!()
      else
        []
      end

    # Create lookup map for efficient ordering
    record_lookup = Map.new(records, fn record -> {record.id, record} end)

    # Preserve Meilisearch result order and attach metadata
    ordered_records =
      hits
      |> Enum.map(fn hit ->
        record_id = hit["id"]

        case Map.get(record_lookup, record_id) do
          nil ->
            Logger.warning(
              "AshMeilisearch: Record #{record_id} found in search but not in database"
            )

            nil

          record ->
            # Attach search metadata using Ash's metadata system
            record =
              if ranking_score = hit["_rankingScore"] do
                Ash.Resource.put_metadata(record, :ranking_score, ranking_score)
              else
                record
              end

            # Attach the raw search result for debugging/analysis
            Ash.Resource.put_metadata(record, :search_result, hit)
        end
      end)
      |> Enum.reject(&is_nil/1)

    # Calculate total count for pagination
    total_count = Map.get(response, "estimatedTotalHits", length(hits))

    {:ok, ordered_records, %{full_count: total_count}}
  end

  defp build_meilisearch_filter(ash_query) do
    case ash_query.filter do
      nil -> nil
      filter -> AshMeilisearch.FilterBuilder.build_filter(filter)
    end
  end

  defp build_meilisearch_sort(ash_query) do
    case ash_query.sort do
      nil -> []
      sorts -> AshMeilisearch.SortBuilder.build_sort(sorts, ash_query.resource)
    end
  end

  # Extract limit from Ash query
  defp get_limit(ash_query) do
    limit = case ash_query.page do
      %{limit: limit} -> limit
      _ -> ash_query.limit || 20
    end

    # Ash expects 1 extra result for page.more? calculation
    limit + 1
  end

  # Extract offset from Ash query  
  defp get_offset(ash_query) do
    case ash_query.page do
      %{offset: offset} -> offset
      _ -> ash_query.offset || 0
    end
  end
end
