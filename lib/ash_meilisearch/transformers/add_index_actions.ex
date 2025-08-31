defmodule AshMeilisearch.Transformers.AddIndexActions do
  @moduledoc """
  Adds index management update actions to resources with Meilisearch configuration.

  Adds :reindex and :configure_index actions for managing the Meilisearch index.
  """

  use Spark.Dsl.Transformer

  def after?(AshMeilisearch.Transformers.AddSearchAction), do: true
  def after?(_), do: false

  def transform(dsl_state) do
    # Access meilisearch config from DSL state map structure
    meilisearch_config = get_in(dsl_state, [Access.key([:meilisearch]), Access.key(:opts)])

    case meilisearch_config do
      config when is_list(config) and length(config) > 0 ->
        if Keyword.has_key?(config, :index) do
          with {:ok, dsl_state} <- add_reindex_action(dsl_state),
               {:ok, dsl_state} <- add_configure_index_action(dsl_state) do
            {:ok, dsl_state}
          end
        else
          {:ok, dsl_state}
        end

      _ ->
        {:ok, dsl_state}
    end
  end

  defp add_reindex_action(dsl_state) do
    opts = [
      accept: [],
      require_atomic?: false,
      manual: {AshMeilisearch.Actions.Reindex, []},
      description: "Rebuild the entire Meilisearch index for this resource"
    ]

    Ash.Resource.Builder.add_action(dsl_state, :update, :reindex, opts)
  end

  defp add_configure_index_action(dsl_state) do
    opts = [
      accept: [],
      require_atomic?: false,
      manual: {AshMeilisearch.Actions.ConfigureIndex, []},
      description: "Update Meilisearch index settings based on resource configuration"
    ]

    Ash.Resource.Builder.add_action(dsl_state, :update, :configure_index, opts)
  end
end
