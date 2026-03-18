# Load and register all connector implementations from lib/connectors

Rails.application.config.to_prepare do
  connectors_dir = Rails.root.join("lib/connectors")

  # Load base classes first
  load connectors_dir.join("registry.rb")
  load connectors_dir.join("base_connector.rb")

  # Load connector implementations
  %w[stub google_calendar microsoft_outlook slack].each do |connector_name|
    connector_file = connectors_dir.join("#{connector_name}.rb")
    load(connector_file) if connector_file.exist?
  end
end
