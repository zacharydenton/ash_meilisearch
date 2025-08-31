defmodule AshMeilisearch do
  @moduledoc """
  An Ash extension that brings full-text search to your resources via Meilisearch.

  Automatically configures Meilisearch indexes based on your resource configuration,
  generates native `:search` read actions that work with normal Ash queries, and 
  keeps indexes in sync with your resources through CRUD hooks.

  ## Usage

      defmodule MyApp.Blog.Post do
        use Ash.Resource,
          domain: MyApp.Blog,
          extensions: [AshMeilisearch]
          
        meilisearch do
          index "posts"
          
          searchable_attributes [:title, :content, author: [:name]]
          filterable_attributes [:status, :published_at]
          sortable_attributes [:title, :published_at]
        end
        
        changes do
          change AshMeilisearch.Changes.UpsertSearchDocument, on: [:create, :update]
          change AshMeilisearch.Changes.DeleteSearchDocument, on: [:destroy]
        end
      end
      
  ## Generated Features

  - `search_document` calculation for Meilisearch indexing
  - `:search` read action for fast search/filter/sort operations
  - `:reindex` and `:configure_index` update actions for index management
  - Automatic conversion of Ash.Filter and Ash.Sort to Meilisearch expressions
  """

  use Spark.Dsl.Extension,
    sections: [AshMeilisearch.Dsl.meilisearch_section()],
    transformers: [
      AshMeilisearch.Transformers.AddSearchDocument,
      AshMeilisearch.Transformers.AddSearchAction,
      AshMeilisearch.Transformers.AddIndexActions
    ],
    verifiers: [
      AshMeilisearch.Verifiers.ValidateSearchConfig
    ]

  # Re-export for convenience - using the actual generated function names
  def index_name(resource) do
    case AshMeilisearch.Info.meilisearch_index(resource) do
      {:ok, value} -> AshMeilisearch.Config.index_name(value)
      value -> AshMeilisearch.Config.index_name(value)
    end
  end

  def action_name(resource) do
    case AshMeilisearch.Info.meilisearch_action_name(resource) do
      {:ok, value} -> value
      value -> value
    end
  end

  defdelegate primary_key(resource), to: AshMeilisearch.Info, as: :meilisearch_primary_key
  defdelegate searchable_attributes(resource), to: AshMeilisearch.Info
  defdelegate filterable_attributes(resource), to: AshMeilisearch.Info
  defdelegate sortable_attributes(resource), to: AshMeilisearch.Info

  @doc """
  Build Meilisearch filter from an Ash.Query.

  ## Examples

      iex> query = Ash.Query.filter(MyApp.Post, status: :published)
      iex> AshMeilisearch.build_filter(query)
      "status = published"
  """
  def build_filter(%Ash.Query{} = query),
    do: AshMeilisearch.FilterBuilder.build_filter(query.filter)

  @doc """
  Build Meilisearch sort array from an Ash.Query.

  ## Examples

      iex> query = Ash.Query.sort(MyApp.Post, [inserted_at: :desc, title: :asc])
      iex> AshMeilisearch.build_sort(query)
      ["inserted_at:desc", "title:asc"]
  """
  def build_sort(%Ash.Query{} = query),
    do: AshMeilisearch.SortBuilder.build_sort(query.sort, query.resource)

  ## Client convenience functions

  @doc """
  Performs a search on the resource's Meilisearch index.

  Automatically resolves the index name from the resource configuration.

  ## Examples

      AshMeilisearch.search(MyApp.Post, "elixir")
      AshMeilisearch.search(MyApp.Post, "phoenix", limit: 10, filter: "status = published")
  """
  def search(resource, query, opts \\ []) do
    index_name = index_name(resource)
    AshMeilisearch.Client.search(index_name, query, opts)
  end

  @doc """
  Performs a multisearch across multiple queries on the resource's index.

  Automatically resolves the index name from the resource configuration.

  ## Examples

      queries = [
        %{q: "elixir", limit: 5},
        %{q: "phoenix", limit: 5}
      ]
      AshMeilisearch.multisearch(MyApp.Post, queries, federation: %{limit: 10})
  """
  def multisearch(resource, queries, opts \\ []) when is_list(queries) do
    index_name = index_name(resource)
    # Add index name to each query if not already present
    queries_with_index =
      Enum.map(queries, fn query ->
        if Map.has_key?(query, :indexUid) do
          query
        else
          Map.put(query, :indexUid, index_name)
        end
      end)

    AshMeilisearch.Client.multisearch(queries_with_index, opts)
  end

  @doc """
  Adds documents to the resource's Meilisearch index.

  Automatically resolves the index name from the resource configuration.

  ## Examples

      documents = [%{id: 1, title: "Hello"}, %{id: 2, title: "World"}]
      AshMeilisearch.add_documents(MyApp.Post, documents)
  """
  def add_documents(resource, documents) do
    index_name = index_name(resource)
    AshMeilisearch.Client.add_documents(index_name, documents)
  end

  @doc """
  Deletes a document from the resource's Meilisearch index.

  Automatically resolves the index name from the resource configuration.

  ## Examples

      AshMeilisearch.delete_document(MyApp.Post, "doc-id-123")
  """
  def delete_document(resource, document_id) do
    index_name = index_name(resource)
    AshMeilisearch.Client.delete_document(index_name, document_id)
  end
end
