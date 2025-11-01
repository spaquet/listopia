# config/initializers/pagy.rb
require "pagy/extras/overflow"

Pagy::DEFAULT[:items] = 25  # items per page
Pagy::DEFAULT[:size]  = [ 1, 4, 4, 1 ]  # nav bar size

# Handle overflow (when page number is out of range)
Pagy::DEFAULT[:overflow] = :last_page
