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
      ]
    ]
  }

  @doc "Returns the meilisearch DSL section definition"
  def meilisearch_section, do: @meilisearch_section
end
