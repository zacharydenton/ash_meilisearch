# AshMeilisearch

An Ash extension that brings full-text search to your resources via [Meilisearch](https://meilisearch.com).

- Automatically configures Meilisearch indexes based on your resource configuration
- Generates `:search` read actions that work with normal Ash queries and pagination
- Converts `Ash.Filter` and `Ash.Sort` to Meilisearch expressions
- Precomputes and denormalizes calculations/aggregates into the search index for blazing fast sorting/filtering
- CRUD hooks keep indexes in sync with your resources automatically

## Install and Configure

Add to your dependencies:

```elixir
def deps do
  [
    {:ash_meilisearch, "~> 0.1.0"}
  ]
end
```

Configure your Meilisearch connection:

```elixir
# config/config.exs
config :ash_meilisearch,
  host: "http://localhost:7700",
  api_key: nil,  # or your API key
  otp_apps: [:my_app]
```

## Add Meilisearch to Resources

Add the extension and configure searchable fields:

```elixir
defmodule MyApp.Blog.Post do
  use Ash.Resource,
    domain: MyApp.Blog,
    extensions: [AshMeilisearch]

  meilisearch do
    index "posts"                    # Index name (required)
    action_name :search              # Generated read action name (optional, defaults to :search)
    
    # Order matters for relevance ranking (title gets higher relevance than content)
    searchable_attributes [
      :title,
      :content,
      author: [:name, :bio],         # Relations
      tags: [:name],
    ]
    
    filterable_attributes [
      :status, 
      :published_at,
      :word_count,                   # Calculations
      :comment_count,                # Aggregations
      author: [:name],
      tags: [:name]
    ]
    
    sortable_attributes [
      :title, 
      :published_at, 
      :word_count,
      :comment_count
    ]
  end

  # Configure CRUD hooks to keep Meilisearch index in sync
  changes do
    change AshMeilisearch.Changes.UpsertSearchDocument, on: [:create, :update]
    change AshMeilisearch.Changes.DeleteSearchDocument, on: [:destroy]
  end
end
```

## Use the Generated Search Action

Now you have a `:search` read action that works exactly like any other Ash read action:

```elixir
results = MyApp.Blog.Post
|> Ash.Query.for_read(:search, %{query: "web development"})
|> Ash.Query.filter(expr(status == :published and inserted_at > ^~D[2023-01-01]))
|> Ash.Query.sort(inserted_at: :desc)
|> Ash.Query.limit(10)
|> Ash.read!()

# Or define a code interface in your domain
define :search_posts, action: :search, args: [:query]

# Then use it with all standard Ash options (including pagination!)
MyApp.Blog.search_posts!("web development", [
  page: [limit: 20, offset: 10],
  load: [:author, :tags],
  query: [
    filter: [status: :published, inserted_at: [gt: ~D[2023-01-01]]],
    sort: [inserted_at: :desc]
  ]
])
```

That's it! Your Ash resources now have full-text search capabilities with automatic sync, relationship indexing, and flexible querying options.

## Initial Data Population

To populate your search index for the first time with existing data, use the included mix task:

```bash
mix ash_meilisearch.reindex MyApp.Blog.Post
```

## API Reference

These functions provide direct access to Meilisearch operations and return raw Meilisearch responses, not Ash resources. For most use cases, you should use the generated `:search` action on your resources instead.

### Search Operations

```elixir
# Perform search on a resource's index
AshMeilisearch.search(MyApp.Post, "search query", limit: 10, filter: "status = published")

# Multisearch across multiple queries
queries = [
  %{q: "elixir", limit: 5},
  %{q: "phoenix", limit: 5}
]
AshMeilisearch.multisearch(MyApp.Post, queries, federation: %{limit: 10})
```

### Index Management

```elixir
# Add documents to index
documents = [%{id: 1, title: "Hello"}, %{id: 2, title: "World"}]
AshMeilisearch.add_documents(MyApp.Post, documents)

# Delete document from index
AshMeilisearch.delete_document(MyApp.Post, "doc-id-123")

# Get index name for resource
AshMeilisearch.index_name(MyApp.Post)
```

### Filter and Sort Translation

```elixir
# Convert Ash query filter to Meilisearch format
query = MyApp.Post
  |> Ash.Query.filter(expr(status == :published and word_count > 500 and author.name == "Alice"))
AshMeilisearch.build_filter(query) # "status = published AND word_count > 500 AND author.name = Alice"

# Convert Ash query sort to Meilisearch format  
query = MyApp.Post
  |> Ash.Query.sort([comment_count: :desc, author.name: :asc, inserted_at: :desc])
AshMeilisearch.build_sort(query) # ["comment_count:desc", "author.name:asc", "inserted_at:desc"]
```
