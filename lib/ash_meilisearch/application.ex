defmodule AshMeilisearch.Application do
  @moduledoc """
  OTP Application for AshMeilisearch.

  Handles application startup, index management, and test cleanup.
  """

  use Application
  require Logger

  def start(_type, _args) do
    # In test environment, create indexes synchronously to avoid race conditions
    # In dev/prod, create indexes asynchronously to not block application startup
    children =
      case AshMeilisearch.Config.environment() do
        :test ->
          ensure_all_indexes()
          []

        _ ->
          [{Task, fn -> ensure_all_indexes() end}]
      end

    opts = [strategy: :one_for_one, name: AshMeilisearch.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def stop(_state) do
    # No cleanup needed anymore since we're using fixed _test suffix
    :ok
  end

  defp ensure_all_indexes do
    # Validate connection first
    AshMeilisearch.Config.validate_connection!()

    # Find all resources with meilisearch configuration
    resources = find_meilisearch_resources()

    for resource <- resources do
      :ok = AshMeilisearch.IndexManager.ensure_index(resource)
    end

    if length(resources) > 0 do
      Logger.info("AshMeilisearch: Initialized #{length(resources)} indexes")
    end
  end

  defp find_meilisearch_resources do
    # Get domains from configuration
    domains = Application.get_env(:ash_meilisearch, :domains, [])

    # Get all resources from configured domains
    domains
    |> Enum.flat_map(fn domain ->
      # Get resources from domain using Ash.Domain.Info
      Ash.Domain.Info.resources(domain)
    end)
    |> Enum.filter(fn resource ->
      # Check if the resource uses AshMeilisearch extension
      AshMeilisearch in Spark.extensions(resource) and
        not is_nil(AshMeilisearch.Info.meilisearch_index(resource))
    end)
  end
end
