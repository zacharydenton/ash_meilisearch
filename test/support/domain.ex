defmodule AshMeilisearch.Test.Domain do
  @moduledoc """
  Test domain for AshMeilisearch integration tests.
  """

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshMeilisearch.Test.Post
    resource AshMeilisearch.Test.Album
    resource AshMeilisearch.Test.Track
  end
end
