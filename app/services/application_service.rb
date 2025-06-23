# app/services/application_service.rb
class ApplicationService
  # Base service class for all application services
  # Provides common functionality and error handling patterns

  def self.call(*args, **kwargs, &block)
    new(*args, **kwargs).call(&block)
  end

  # Result object for service responses
  class Result
    attr_reader :success, :data, :errors, :message

    def initialize(success:, data: nil, errors: [], message: nil)
      @success = success
      @data = data
      @errors = Array(errors)
      @message = message
    end

    def success?
      @success
    end

    def failure?
      !@success
    end

    def self.success(data: nil, message: nil)
      new(success: true, data: data, message: message)
    end

    def self.failure(errors: [], message: nil)
      new(success: false, errors: Array(errors), message: message)
    end
  end

  private

  # Helper method to create success result
  def success(data: nil, message: nil)
    Result.success(data: data, message: message)
  end

  # Helper method to create failure result
  def failure(errors: [], message: nil)
    Result.failure(errors: errors, message: message)
  end
end
