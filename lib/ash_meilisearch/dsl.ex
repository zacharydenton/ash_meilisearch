defmodule AshMeilisearch.Dsl do
  @moduledoc """
  DSL definition for AshMeilisearch extension.
  """

  @meilisearch_section %Spark.Dsl.Section{
    name: :meilisearch,
    describe: """
    Configure Meilisearch integration for this resource.

    Defines the index name and other settings for auto-generated search functionality.
    """,
    examples: [
      """
      meilisearch do
        index "posts"
        searchable_attributes [:title, :content]
        filterable_attributes [:status, :published_at]
        sortable_attributes [:title, :published_at]
      end
      """,
      """
      meilisearch do
        index "albums"
        action_name :search_albums
        searchable_attributes [:title, :description]
        filterable_attributes [:title, :artist, :year]
        sortable_attributes [:title, :year, :created_at]
      end
      """
    ],
    schema: [
      index: [
        type: :string,
        required: true,
        doc: """
        The Meilisearch index name for this resource.
        This will be used for all search operations and index management.
        """
      ],
      action_name: [
        type: :atom,
        default: :search,
        doc: """
        Name of the auto-generated search read action.
        Defaults to `:search`.
        """
      ],
      searchable_attributes: [
        type: {:list, {:or, [:atom, {:tuple, [:atom, {:list, :atom}]}]}},
        default: [],
        doc: """
        List of attributes and relationships that should be searchable in Meilisearch.
        Supports simple attributes (`:title`) and relationship attributes (`tags: [:name]`).
        """
      ],
      filterable_attributes: [
        type: {:list, {:or, [:atom, {:tuple, [:atom, {:list, :atom}]}]}},
        default: [],
        doc: """
        List of attributes and relationships that should be filterable in Meilisearch.
        Supports simple attributes (`:studio_id`) and relationship attributes (`studio: [:name]`).
        """
      ],
      sortable_attributes: [
        type: {:list, {:or, [:atom, {:tuple, [:atom, {:list, :atom}]}]}},
        default: [],
        doc: """
        List of attributes and relationships that should be sortable in Meilisearch.
        Supports simple attributes (`:title`) and relationship attributes (`studio: [:name]`).
        """
      ],
      ranking_rules: [
        type: {:list, :string},
        default: [],
        doc: """
        Custom ranking rules for the index. When empty, Meilisearch defaults are used.
        Example: `["words", "attribute", "proximity", "exactness", "typo", "sort"]`
        """
      ],
      stop_words: [
        type: {:list, :string},
        default: [],
        doc: """
        Words that are ignored during search. Useful for removing noise from common words.
        Example: `["the", "a", "an", "in", "on", "at"]`
        """
      ],
      synonyms: [
        type: :map,
        default: %{},
        doc: """
        Synonym mappings for the index. Keys are words, values are lists of synonyms.
        Example: `%{"film" => ["movie", "picture"], "tv" => ["television"]}`
        """
      ],
      typo_tolerance: [
        type: :map,
        default: %{},
        doc: """
        Typo tolerance settings for the index. Passed directly to Meilisearch as `typoTolerance`.
        Example: `%{disableOnAttributes: ["code"], minWordSizeForTypos: %{oneTypo: 5, twoTypos: 9}}`
        """
      ],
      embedders: [
        type: :map,
        default: %{},
        doc: """
        Embedder configurations for vector search. Keys are embedder names, values are config maps.
        For user-provided embeddings, set `source: "userProvided"` and `dimensions: N`.
        Example: `%{"default" => %{source: "userProvided", dimensions: 384}}`
        """
      ],
      embedding_function: [
        type: {:or, [{:fun, 1}, nil]},
        default: nil,
        doc: """
        A function that takes a record and returns a vector (list of floats) for embedding.
        When set, the upsert hook will call this function to generate `_vectors` for documents.
        Example: `&MyApp.ML.TextEmbedding.embed_scene/1`
        """
      ]
    ]
  }

  @doc "Returns the meilisearch DSL section definition"
  def meilisearch_section, do: @meilisearch_section
end
