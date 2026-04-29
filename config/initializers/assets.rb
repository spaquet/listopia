# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# Add additional assets to the asset load path.
# Rails.application.config.assets.paths << Emoji.images_path

# cssbundling-rails compiles app/assets/stylesheets/application.tailwind.css
# into app/assets/builds/application.css. Exclude the source stylesheet
# directory from Propshaft so raw Tailwind input files are not linked directly.
Rails.application.config.assets.excluded_paths << Rails.root.join("app/assets/stylesheets")
