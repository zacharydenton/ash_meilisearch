import Config

if Mix.env() == :test do
  # AshMeilisearch configuration for tests
  config :ash_meilisearch,
    host: "http://localhost:7700",
    api_key: nil,
    domains: [AshMeilisearch.Test.Domain]

  # Ash configuration for tests
  config :ash, :validate_domain_resource_inclusion?, false
  config :ash, :validate_domain_config_inclusion?, false
end
