require "rails_helper"

RSpec.describe Connectors::Google::FileService, type: :service do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, creator: user) }
  let(:account) { create(:connectors_account, :with_tokens, provider: "google_drive", user: user, organization: organization) }

  before do
    Current.user = user
    Current.organization = organization
  end

  after { Current.reset }

  let(:service) { described_class.new(connector_account: account) }

  describe "#fetch_about" do
    context "with successful API response" do
      before do
        allow_any_instance_of(Net::HTTP).to receive(:request).and_return(
          instance_double(Net::HTTPSuccess,
            is_a?: true,
            body: {
              user: { displayName: "John Doe", emailAddress: "john@example.com" },
              storageQuota: { limit: "15000000000", usage: "1234567890" }
            }.to_json
          )
        )
      end

      it "returns user and storage quota information" do
        about = service.fetch_about

        expect(about["user"]["displayName"]).to eq("John Doe")
        expect(about["storageQuota"]["limit"]).to eq("15000000000")
      end

      it "creates sync log entry" do
        expect {
          service.fetch_about
        }.to change(Connectors::SyncLog, :count).by(1)

        log = Connectors::SyncLog.last
        expect(log.operation).to eq("fetch_about")
        expect(log.status).to eq("success")
        expect(log.records_processed).to eq(1)
      end
    end

    context "with API error" do
      before do
        allow_any_instance_of(Net::HTTP).to receive(:request).and_return(
          instance_double(Net::HTTPSuccess,
            is_a?: true,
            body: { error: { message: "unauthorized" } }.to_json
          )
        )
      end

      it "raises error with API error message" do
        expect {
          service.fetch_about
        }.to raise_error(/Google Drive API error/)
      end
    end
  end

  describe "#list_files" do
    context "with no search query" do
      before do
        allow_any_instance_of(Net::HTTP).to receive(:request).and_return(
          instance_double(Net::HTTPSuccess,
            is_a?: true,
            body: {
              files: [
                { id: "file1", name: "Document.pdf", mimeType: "application/pdf" },
                { id: "file2", name: "Spreadsheet.xlsx", mimeType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" }
              ],
              nextPageToken: "token123"
            }.to_json
          )
        )
      end

      it "returns list of files with pagination token" do
        result = service.list_files

        expect(result[:files].count).to eq(2)
        expect(result[:files][0]["name"]).to eq("Document.pdf")
        expect(result[:next_page_token]).to eq("token123")
      end
    end

    context "with search query" do
      before do
        allow_any_instance_of(Net::HTTP).to receive(:request).and_return(
          instance_double(Net::HTTPSuccess,
            is_a?: true,
            body: {
              files: [
                { id: "file3", name: "report.pdf", mimeType: "application/pdf" }
              ]
            }.to_json
          )
        )
      end

      it "returns filtered files matching search query" do
        result = service.list_files(query: "report")

        expect(result[:files].count).to eq(1)
        expect(result[:files][0]["name"]).to eq("report.pdf")
      end
    end

    context "with pagination token" do
      before do
        allow_any_instance_of(Net::HTTP).to receive(:request).and_return(
          instance_double(Net::HTTPSuccess,
            is_a?: true,
            body: {
              files: [
                { id: "file4", name: "Image.jpg", mimeType: "image/jpeg" }
              ]
            }.to_json
          )
        )
      end

      it "returns next page of files" do
        result = service.list_files(page_token: "token123")

        expect(result[:files].count).to eq(1)
        expect(result[:files][0]["name"]).to eq("Image.jpg")
      end
    end
  end

  describe "#get_file" do
    context "with valid file ID" do
      before do
        allow_any_instance_of(Net::HTTP).to receive(:request).and_return(
          instance_double(Net::HTTPSuccess,
            is_a?: true,
            body: {
              id: "file1",
              name: "Document.pdf",
              mimeType: "application/pdf",
              size: "1024000",
              webViewLink: "https://drive.google.com/file/d/file1/view",
              modifiedTime: "2024-03-19T10:00:00Z",
              owners: [{ displayName: "John Doe" }]
            }.to_json
          )
        )
      end

      it "returns file metadata" do
        file = service.get_file("file1")

        expect(file["id"]).to eq("file1")
        expect(file["name"]).to eq("Document.pdf")
        expect(file["size"]).to eq("1024000")
        expect(file["webViewLink"]).to include("drive.google.com")
      end

      it "creates sync log entry" do
        expect {
          service.get_file("file1")
        }.to change(Connectors::SyncLog, :count).by(1)

        log = Connectors::SyncLog.last
        expect(log.operation).to eq("get_file")
        expect(log.records_processed).to eq(1)
      end
    end

    context "with API error" do
      before do
        allow_any_instance_of(Net::HTTP).to receive(:request).and_return(
          instance_double(Net::HTTPSuccess,
            is_a?: true,
            body: { error: { message: "File not found" } }.to_json
          )
        )
      end

      it "raises error for missing file" do
        expect {
          service.get_file("invalid_file_id")
        }.to raise_error(/Google Drive API error/)
      end
    end
  end

  describe "#get_download_url" do
    it "returns properly formatted download URL" do
      allow_any_instance_of(described_class).to receive(:get_file).and_return(
        { "id" => "file1", "name" => "Document.pdf" }
      )

      url = service.get_download_url("file1")

      expect(url).to include("googleapis.com/drive/v3/files/file1")
      expect(url).to include("alt=media")
    end
  end
end
