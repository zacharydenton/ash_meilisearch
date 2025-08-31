ExUnit.start()

# Configuration for AshMeilisearch tests
Application.put_env(:ash_meilisearch, :host, "http://localhost:7700")
Application.put_env(:ash_meilisearch, :api_key, nil)
