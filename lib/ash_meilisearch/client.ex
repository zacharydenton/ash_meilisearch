defmodule AshMeilisearch.Client do
  @moduledoc """
  Meilisearch client functionality for AshMeilisearch extension.

  Provides low-level client operations for interacting with Meilisearch.
  """

  require Logger

  @doc """
  Gets the Meilisearch base URL and headers from configuration.

  Uses AshMeilisearch.Config for centralized configuration management.
  """
  def config do
    host = AshMeilisearch.Config.host()
    api_key = AshMeilisearch.Config.api_key()

    headers =
      if api_key do
        [{"Authorization", "Bearer #{api_key}"}, {"Content-Type", "application/json"}]
      else
        [{"Content-Type", "application/json"}]
      end

    {host, headers}
  end

  @doc """
  Checks Meilisearch server health.
  """
  def health do
    {endpoint, headers} = config()

    Req.get("#{endpoint}/health", headers: headers) |> handle_meilisearch_response()
  end

  @doc """
  Indexes documents to a Meilisearch index.

  ## Parameters
    - index_name: The name of the Meilisearch index
    - documents: List of documents to index (must have an "id" field)
  """
  def index_documents(index_name, documents) when is_list(documents) do
    with :ok <- ensure_index(index_name, "id"),
         {:ok, result} <- add_documents(index_name, documents) do
      {:ok, result}
    else
      error -> error
    end
  end

  def index_documents(index_name, documents, _app) when is_list(documents) do
    index_documents(index_name, documents)
  end

  @doc """
  Creates an index if it doesn't exist.
  """
  def ensure_index(index_name, primary_key \\ "id") do
    {endpoint, headers} = config()

    # Check if index exists
    case Req.get("#{endpoint}/indexes/#{index_name}", headers: headers) do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, %{status: 404}} ->
        Logger.info("Creating Meilisearch index: #{index_name}")

        case Req.post("#{endpoint}/indexes",
               headers: headers,
               json: %{uid: index_name, primaryKey: primary_key}
             ) do
          {:ok, %{status: status}} when status in [200, 201, 202] ->
            :ok

          {:ok, %{status: status, body: body}} ->
            {:error, "Failed to create index (#{status}): #{inspect(body)}"}

          {:error, error} ->
            {:error, "Index creation request failed: #{inspect(error)}"}
        end

      {:ok, %{status: status, body: body}} ->
        {:error, "Index check failed (#{status}): #{inspect(body)}"}

      {:error, error} ->
        {:error, "Index check request failed: #{inspect(error)}"}
    end
  end

  def ensure_index(index_name, primary_key, _app) do
    ensure_index(index_name, primary_key)
  end

  @doc """
  Updates index settings.
  """
  def update_setting(index_name, setting, value) do
    {endpoint, headers} = config()
    url = "#{endpoint}/indexes/#{index_name}/settings/#{setting}"

    Req.put(url, headers: headers, json: value) |> handle_meilisearch_response()
  end

  def update_setting(index_name, setting, value, _app) do
    update_setting(index_name, setting, value)
  end

  @doc """
  Adds documents to an index.
  """
  def add_documents(index_name, documents) do
    {endpoint, headers} = config()
    url = "#{endpoint}/indexes/#{index_name}/documents"

    Req.post(url, headers: headers, json: documents) |> handle_meilisearch_response()
  end

  def add_documents(index_name, documents, _app) do
    add_documents(index_name, documents)
  end

  @doc """
  Deletes a single document from an index by ID.
  """
  def delete_document(index_name, document_id) do
    {endpoint, headers} = config()
    url = "#{endpoint}/indexes/#{index_name}/documents/#{document_id}"

    Req.delete(url, headers: headers) |> handle_meilisearch_response()
  end

  @doc """
  Searches an index using a query string.
  """
  def search(index_name, query, opts \\ []) when is_binary(query) do
    # Start with base parameters
    search_params =
      %{
        q: query
      }
      |> Map.merge(Enum.into(opts, %{}))

    {endpoint, headers} = config()
    url = "#{endpoint}/indexes/#{index_name}/search"

    Req.post(url, headers: headers, json: search_params) |> handle_meilisearch_response()
  end

  def search(index_name, query, opts, _app) when is_binary(query) do
    search(index_name, query, opts)
  end

  @doc """
  Performs multiple searches in parallel using Meilisearch's multi-search endpoint.
  """
  def multisearch(queries, opts \\ []) when is_list(queries) do
    {endpoint, headers} = config()
    url = "#{endpoint}/multi-search"

    request_body = %{queries: queries}

    # Add federation if requested
    request_body =
      if federation_opts = Keyword.get(opts, :federation) do
        federation_config =
          case federation_opts do
            true -> %{}
            false -> nil
            map when is_map(map) -> map
          end

        if federation_config,
          do: Map.put(request_body, :federation, federation_config),
          else: request_body
      else
        request_body
      end

    Req.post(url, headers: headers, json: request_body) |> handle_meilisearch_response()
  end

  def multisearch(queries, opts, _app) when is_list(queries) do
    multisearch(queries, opts)
  end

  @doc """
  Gets information about a specific index.
  """
  def get_index(index_name) do
    {endpoint, headers} = config()
    url = "#{endpoint}/indexes/#{index_name}"

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: 404, body: body}} -> {:error, body}
      {:ok, %{body: body}} -> {:error, body}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Creates a new index.
  """
  def create_index(index_name, opts \\ %{}) do
    {endpoint, headers} = config()
    url = "#{endpoint}/indexes"

    body = Map.merge(%{uid: index_name}, opts)

    case Req.post(url, headers: headers, json: body) do
      {:ok, %{status: status, body: body}} when status in [200, 201, 202] ->
        {:ok, body}

      {:ok, %{body: body}} ->
        {:error, body}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Deletes an index.
  """
  def delete_index(index_name) do
    {endpoint, headers} = config()
    url = "#{endpoint}/indexes/#{index_name}"

    case Req.delete(url, headers: headers) do
      {:ok, %{status: status, body: body}} when status in [200, 202] ->
        {:ok, body}

      {:ok, %{body: body}} ->
        {:error, body}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Gets index settings.
  """
  def get_index_settings(index_name) do
    {endpoint, headers} = config()
    url = "#{endpoint}/indexes/#{index_name}/settings"

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{body: body}} -> {:error, body}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Updates index settings.
  """
  def update_index_settings(index_name, settings) do
    {endpoint, headers} = config()
    url = "#{endpoint}/indexes/#{index_name}/settings"

    case Req.patch(url, headers: headers, json: settings) do
      {:ok, %{status: status, body: body}} when status in [200, 202] ->
        {:ok, body}

      {:ok, %{body: body}} ->
        {:error, body}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Deletes all documents in an index.
  """
  def clear_index(index_name) do
    {endpoint, headers} = config()
    url = "#{endpoint}/indexes/#{index_name}/documents"

    Req.delete(url, headers: headers)
    |> handle_meilisearch_response()
  end

  defp handle_meilisearch_response(response) do
    case response do
      {:ok, %{status: status, body: body}} when status in [200, 201, 202] ->
        {:ok, body}

      {:ok, %{status: status, body: body}} when status >= 400 ->
        {:error, body}

      {:ok, %{body: body}} ->
        {:search_error, body}

      {:error, error} ->
        {:error, error}
    end
  end
end
