defmodule AshMeilisearch.Transformers.AddSearchAction do
  @moduledoc """
  Adds a manual search read action to resources with Meilisearch configuration.

  The action uses Meilisearch for fast search, filtering, and sorting while
  returning proper Ash structs loaded from the primary data layer.
  """

  use Spark.Dsl.Transformer

  def after?(AshMeilisearch.Transformers.AddSearchDocument), do: true
  def after?(_), do: false

  def transform(dsl_state) do
    # Access meilisearch config from DSL state map structure
    meilisearch_config = get_in(dsl_state, [Access.key([:meilisearch]), Access.key(:opts)])

    case meilisearch_config do
      config when is_list(config) and length(config) > 0 ->
        if Keyword.has_key?(config, :index) do
          action_name = Keyword.get(config, :action_name, :search)
          add_search_action(dsl_state, action_name)
        else
          {:ok, dsl_state}
        end

      _ ->
        {:ok, dsl_state}
    end
  end

  defp add_search_action(dsl_state, action_name) do
    # Build polymorphic query argument - can be string for single search or list for multisearch
    {:ok, query_arg} =
      Ash.Resource.Builder.build_action_argument(:query, :union,
        allow_nil?: false,
        public?: true,
        constraints: [
          types: [
            ci_string: [
              type: :ci_string,
              constraints: [allow_empty?: true]
            ],
            queries: [
              type: {:array, :map}
            ]
          ]
        ],
        description:
          "Search query - string for single search or list of query maps for multisearch"
      )

    # Add federation options for multisearch
    {:ok, federation_arg} =
      Ash.Resource.Builder.build_action_argument(:federation, :map,
        allow_nil?: true,
        public?: true,
        description: "Federation options for multisearch (limit, offset, etc.)"
      )

    # Build pagination options properly
    {:ok, pagination} =
      Ash.Resource.Builder.build_pagination(
        offset?: true,
        countable: true,
        default_limit: 20,
        max_page_size: 1000
      )

    opts = [
      arguments: [query_arg, federation_arg],
      pagination: pagination,
      manual: {AshMeilisearch.Actions.Search, []},
      description:
        "Auto-generated Meilisearch search action supporting both single search and multisearch with federation"
    ]

    Ash.Resource.Builder.add_action(dsl_state, :read, action_name, opts)
  end
end
