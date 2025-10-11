# config/initializers/logidze.rb

# Logidze to always store history data in a separate table for all models
# (instead of in a JSONB column in the same table).
# This is more efficient for large records and allows more flexible queries.
#
Logidze.log_data_placement = :detached


# Avoid loading log_data by default (and load it on demand)
Logidze.ignore_log_data_by_default = true
