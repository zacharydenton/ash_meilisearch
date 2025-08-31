defmodule AshMeilisearch.Config do
  @moduledoc """
  Configuration management for AshMeilisearch extension.

  Handles environment-specific configuration and index naming conventions.
  """

  require Logger

  @doc """
  Get the configured Meilisearch host URL.
  """
  def host do
    Application.get_env(:ash_meilisearch, :host) || raise_config_error(:host)
  end

  @doc """
  Get the configured Meilisearch API key.
  """
  def api_key do
    Application.get_env(:ash_meilisearch, :api_key)
  end

  @doc """
  Get the configured index suffix for the current environment.

  Defaults to the Mix environment with underscore prefix.
  """
  def index_suffix do
    Application.get_env(:ash_meilisearch, :index_suffix) || "_#{environment()}"
  end

  @doc """
  Get the current Mix environment.
  """
  def environment do
    Mix.env()
  end

  # Build the full index name with environment suffix (private helper)
  defp env_index_name(base_name, suffix \\ nil) do
    base_suffix = index_suffix()

    case suffix do
      nil -> "#{base_name}#{base_suffix}"
      custom -> "#{base_name}#{base_suffix}#{custom}"
    end
  end

  @doc """
  Get the test process identifier for index isolation.

  Returns a unique string based on the current process to ensure
  test isolation similar to Ecto.Sandbox.
  """
  def test_suffix do
    # No longer using PID-based suffixes for simplicity
    nil
  end

  @doc """
  Build index name with environment suffix and test isolation if needed.

  ## Examples

      # In test environment
      iex> AshMeilisearch.Config.index_name("albums")
      "albums_test_0_123_456"  # PID-based suffix

      # In dev/prod environment  
      iex> AshMeilisearch.Config.index_name("albums")
      "albums_dev"  # No test suffix

  """
  def index_name(base_name) do
    case test_suffix() do
      nil -> env_index_name(base_name)
      suffix -> env_index_name(base_name, suffix)
    end
  end

  @doc """
  Validate that Meilisearch is properly configured and reachable.

  This should be called during application startup to ensure
  the extension is properly configured.
  """
  def validate_connection! do
    host_url = host()

    case AshMeilisearch.Client.health() do
      {:ok, _} ->
        Logger.info("AshMeilisearch: Connected to #{host_url}")
        :ok

      {:error, reason} ->
        error_msg =
          "AshMeilisearch: Failed to connect to Meilisearch at #{host_url}: #{inspect(reason)}"

        Logger.error(error_msg)
        raise error_msg
    end
  end

  # Private functions

  defp raise_config_error(:host) do
    raise """
    AshMeilisearch configuration error: :host is required.

    Add to your config/dev.exs, config/test.exs, config/prod.exs:

        config :ash_meilisearch,
          host: "http://localhost:7700",
          api_key: nil  # or your API key

    """
  end
end
