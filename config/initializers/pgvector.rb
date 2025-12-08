# Register pgvector type with ActiveRecord
# This ensures Rails recognizes the 'vector' type from pgvector extension

# Register a custom type for vector columns
# This prevents the "unknown OID" warning when the vector type is used
class VectorType < ActiveRecord::Type::String
  # Treat vectors as strings for now
  # In the future, we could implement custom serialization/deserialization

  def type
    :vector
  end
end

# Register the custom type with Rails
ActiveRecord::Type.register(:vector, VectorType)

# Also register it with the PostgreSQL adapter
if defined?(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter)
  ActiveRecord::ConnectionAdapters::PostgreSQLAdapter::NATIVE_DATABASE_TYPES[:vector] = { name: 'vector' }
end
