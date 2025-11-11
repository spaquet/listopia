# spec/support/capybara.rb
require 'capybara/cuprite'

# Register Cuprite driver
Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(
    app,
    browser_options: { 'no-sandbox': nil },
    timeout: 10,
    process_timeout: 15,
    inspector: false,
    headless: true
  )
end

# Register debug driver for troubleshooting
Capybara.register_driver(:cuprite_debug) do |app|
  Capybara::Cuprite::Driver.new(
    app,
    browser_options: { 'no-sandbox': nil },
    timeout: 10,
    process_timeout: 15,
    inspector: true,
    headless: false
  )
end

# Use Cuprite for JavaScript tests
Capybara.default_driver = :cuprite
Capybara.javascript_driver = :cuprite

# Default wait time
Capybara.default_max_wait_time = 5
