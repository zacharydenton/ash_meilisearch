defmodule AshMeilisearch.Verifiers.ValidateSearchConfig do
  @moduledoc """
  Validates that Meilisearch configuration is correct.

  Runs after all transformers to validate the final configuration.
  """

  use Spark.Dsl.Verifier

  @impl true
  def verify(dsl_state) do
    # Use proper transformer functions to access DSL state
    case Spark.Dsl.Transformer.get_option(dsl_state, [:meilisearch], :index) do
      nil ->
        # No meilisearch configured, that's fine
        :ok

      index_name when is_binary(index_name) ->
        # Basic validation passed
        validate_single_primary_key(dsl_state)

      invalid ->
        {:error,
         Spark.Error.DslError.exception(
           module: Spark.Dsl.Transformer.get_persisted(dsl_state, :module),
           message: "Invalid index name: #{inspect(invalid)}. Must be a string.",
           path: [:meilisearch, :index]
         )}
    end
  end

  defp validate_single_primary_key(dsl_state) do
    # Get attributes that are marked as primary key
    attributes = Spark.Dsl.Transformer.get_entities(dsl_state, [:attributes]) || []

    primary_key_attrs =
      attributes
      |> Enum.filter(& &1.primary_key?)
      |> Enum.map(& &1.name)

    case primary_key_attrs do
      [] ->
        {:error,
         Spark.Error.DslError.exception(
           module: Spark.Dsl.Transformer.get_persisted(dsl_state, :module),
           message:
             "Meilisearch requires a primary key, but no primary key is defined on the resource.",
           path: [:meilisearch]
         )}

      [_single] ->
        # Single primary key is valid
        :ok

      multiple ->
        {:error,
         Spark.Error.DslError.exception(
           module: Spark.Dsl.Transformer.get_persisted(dsl_state, :module),
           message:
             "Meilisearch only supports single-field primary keys, but this resource has composite primary key: #{inspect(multiple)}. Consider using a single UUID primary key instead.",
           path: [:meilisearch]
         )}
    end
  end
end
