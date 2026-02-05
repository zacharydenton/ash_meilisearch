defmodule Mix.Tasks.AshMeilisearch.Reindex do
  @shortdoc "Reindex all records of an AshMeilisearch-enabled resource"
  @moduledoc """
  Reindex all records of a given AshMeilisearch-enabled resource.

  ## Usage

      mix ash_meilisearch.reindex MyApp.Blog.Post
      mix ash_meilisearch.reindex MyApp.Blog.Post --batch-size 200

  ## Options

    * `--batch-size` - Number of records per batch (default: 100)
    * `--help` - Show help message

  The task uses keyset pagination for memory-efficient processing of large datasets.
  """

  use Mix.Task

  require Ash.Query

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    Logger.configure(level: :warning)

    {options, args, _} =
      OptionParser.parse(args,
        switches: [batch_size: :integer, help: :boolean],
        aliases: [b: :batch_size, h: :help]
      )

    if options[:help] || length(args) == 0 do
      print_help()
      System.halt(0)
    end

    resource_module_name = List.first(args)
    resource_module = Module.concat([resource_module_name])
    batch_size = options[:batch_size] || 100

    validate_resource!(resource_module, resource_module_name)

    Mix.shell().info("Reindexing #{resource_module_name}...")

    total_count = Ash.count!(Ash.Query.new(resource_module))
    Mix.shell().info("Found #{total_count} records")

    if total_count == 0 do
      Mix.shell().info("No records to reindex.")
      System.halt(0)
    end

    Mix.shell().info("Processing #{total_count} records in batches of #{batch_size}")

    start_time = System.monotonic_time(:millisecond)
    final_stats = process_batches(resource_module, batch_size, total_count)
    elapsed_seconds = div(System.monotonic_time(:millisecond) - start_time, 1000)

    records_per_second =
      if elapsed_seconds > 0,
        do: Float.round(final_stats.successful / elapsed_seconds, 1),
        else: "N/A"

    Mix.shell().info(
      "Reindex complete. Processed #{final_stats.successful}/#{total_count} records in #{elapsed_seconds}s (#{records_per_second} records/sec)"
    )

    if final_stats.failed > 0 do
      Mix.shell().error("#{final_stats.failed} records failed to reindex")

      final_stats.failed_ids
      |> Enum.take(10)
      |> Enum.each(&Mix.shell().error("  Failed ID: #{&1}"))

      if length(final_stats.failed_ids) > 10 do
        Mix.shell().error("  ... and #{length(final_stats.failed_ids) - 10} more")
      end
    end
  end

  defp validate_resource!(resource_module, resource_module_name) do
    unless Code.ensure_loaded?(resource_module) and
             function_exported?(resource_module, :spark_dsl_config, 0) do
      Mix.shell().error("Error: '#{resource_module_name}' is not an Ash resource")
      System.halt(1)
    end

    unless AshMeilisearch.Info.meilisearch_configured?(resource_module) do
      Mix.shell().error(
        "Error: '#{resource_module_name}' does not have AshMeilisearch configured"
      )

      System.halt(1)
    end

    unless Ash.Resource.Info.action(resource_module, :reindex) do
      Mix.shell().error("Error: '#{resource_module_name}' does not have a :reindex action")
      System.halt(1)
    end
  end

  defp print_help do
    Mix.shell().info("""
    AshMeilisearch Resource Reindex Task

    Usage: mix ash_meilisearch.reindex [ResourceModule] [options]

    Arguments:
      ResourceModule    The Ash resource module to reindex (e.g., MyApp.Blog.Post)

    Options:
      -b, --batch-size  Number of records per batch (default: 100)
      -h, --help        Show this help message
    """)
  end

  defp process_batches(
         resource_module,
         batch_size,
         total_count,
         page \\ nil,
         acc \\ %{successful: 0, failed: 0, failed_ids: [], start_time: nil, last_pct: 0}
       ) do
    acc =
      if acc.start_time do
        acc
      else
        Map.put(acc, :start_time, System.monotonic_time(:millisecond))
      end

    db_start = System.monotonic_time(:millisecond)
    page =
      if page do
        Ash.page!(page, :next)
      else
        query =
          resource_module
          |> Ash.Query.new()
          |> Ash.Query.select([:id])
          |> Ash.Query.load(:search_document)
          |> Ash.Query.sort(id: :asc)
          |> Ash.Query.page(limit: batch_size)

        Ash.read!(query)
      end
    db_ms = System.monotonic_time(:millisecond) - db_start

    embedding_fn = AshMeilisearch.Info.meilisearch_embedding_function(resource_module)
    embedders = AshMeilisearch.Info.meilisearch_embedders(resource_module)

    valid_documents =
      Enum.filter(page.results, fn record ->
        record.search_document not in [nil, %{}]
      end)

    new_acc =
      if length(valid_documents) > 0 do
        embed_start = System.monotonic_time(:millisecond)
        batch_documents =
          valid_documents
          |> Enum.map(& &1.search_document)
          |> maybe_attach_vectors(embedding_fn, embedders)
        embed_ms = System.monotonic_time(:millisecond) - embed_start

        meili_start = System.monotonic_time(:millisecond)
        case AshMeilisearch.add_documents(resource_module, batch_documents) do
          {:ok, _task} ->
            meili_ms = System.monotonic_time(:millisecond) - meili_start
            new_successful = acc.successful + length(valid_documents)
            current_pct = div(new_successful * 1000, total_count)

            new_acc =
              if current_pct > acc.last_pct do
                elapsed_ms = System.monotonic_time(:millisecond) - acc.start_time
                elapsed_sec = max(elapsed_ms / 1000, 0.1)
                rate = Float.round(new_successful / elapsed_sec, 1)
                pct_display = Float.round(current_pct / 10, 1)
                Mix.shell().info("  #{pct_display}% - #{new_successful}/#{total_count} (#{rate} rec/s) [db:#{db_ms}ms embed:#{embed_ms}ms meili:#{meili_ms}ms]")
                %{acc | successful: new_successful, last_pct: current_pct}
              else
                %{acc | successful: new_successful}
              end

            new_acc

          {:error, error} ->
            Mix.shell().error("Batch failed: #{inspect(error)}")
            failed_ids = Enum.map(page.results, & &1.id)

            %{
              acc
              | failed: acc.failed + length(page.results),
                failed_ids: acc.failed_ids ++ failed_ids
            }
        end
      else
        acc
      end

    if page.more? do
      process_batches(resource_module, batch_size, total_count, page, new_acc)
    else
      new_acc
    end
  end

  defp maybe_attach_vectors(documents, nil, _embedders), do: documents

  defp maybe_attach_vectors(documents, _fn, embedders) when embedders == %{},
    do: documents

  defp maybe_attach_vectors(documents, embedding_fn, embedders) do
    embedder_name = embedders |> Map.keys() |> List.first() |> to_string()

    # Nx.Serving.batched_run handles batching internally when called concurrently
    documents
    |> Task.async_stream(
      fn doc ->
        case embedding_fn.(doc) do
          vector when is_list(vector) and length(vector) > 0 ->
            Map.put(doc, "_vectors", %{embedder_name => vector})

          _ ->
            doc
        end
      end,
      ordered: true,
      max_concurrency: System.schedulers_online()
    )
    |> Enum.map(fn {:ok, doc} -> doc end)
  end
end
