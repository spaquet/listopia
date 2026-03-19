APP_VERSION = File.read(Rails.root.join("VERSION")).strip
APP_BUILD = `git rev-parse --short HEAD 2>/dev/null`.strip.presence || "dev"
