module Connectors
  module Storage
    module GoogleDrive
      # Controller for Google Drive file browsing
      class FilesController < Connectors::BaseController
        before_action :load_connector_account
        before_action :load_service

        # GET /connectors/storage/google_drive/files
        def index
          authorize @connector_account

          @query = params[:q]
          @page_token = params[:page_token]
          @files_data = fetch_files(@query, @page_token)
          @files = @files_data[:files]
          @next_page_token = @files_data[:next_page_token]
        end

        # GET /connectors/storage/google_drive/files/:id
        def show
          authorize @connector_account

          @file = fetch_file(params[:id])
        end

        private

        def load_connector_account
          @connector_account = ::Connectors::Account.find(params[:connector_account_id])
          authorize @connector_account, policy_class: ::Connectors::AccountPolicy
        end

        def load_service
          @service = ::Connectors::Google::FileService.new(
            connector_account: @connector_account
          )
        end

        def fetch_files(query, page_token)
          begin
            @service.list_files(query: query, page_token: page_token)
          rescue StandardError => e
            Rails.logger.error("Failed to fetch Google Drive files: #{e.message}")
            { files: [], next_page_token: nil }
          end
        end

        def fetch_file(file_id)
          begin
            @service.get_file(file_id)
          rescue StandardError => e
            Rails.logger.error("Failed to fetch Google Drive file: #{e.message}")
            {}
          end
        end
      end
    end
  end
end
