require 'capybara/cuprite'

Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(
    app,
    browser_options: { 'no-sandbox': nil },
    timeout: 30,
    process_timeout: 60,
    inspector: false,
    headless: true
  )
end

Capybara.register_driver(:cuprite_debug) do |app|
  Capybara::Cuprite::Driver.new(
    app,
    browser_options: { 'no-sandbox': nil },
    timeout: 30,
    process_timeout: 60,
    inspector: true,
    headless: false
  )
end

Capybara.default_driver = :cuprite
Capybara.javascript_driver = :cuprite
Capybara.default_max_wait_time = 10
