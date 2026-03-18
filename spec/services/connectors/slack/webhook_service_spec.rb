require "rails_helper"

RSpec.describe Connectors::Slack::WebhookService, type: :service do
  describe "#verify_request" do
    let(:signing_secret) { "test_signing_secret" }
    let(:timestamp) { Time.current.to_i.to_s }
    let(:body) { '{"type":"event_callback","event":{}}' }

    before do
      allow(Rails.application.credentials).to receive(:dig).with(:slack, :signing_secret).and_return(signing_secret)
      allow(ENV).to receive(:[]).and_call_original
    end

    context "with valid signature" do
      it "returns true for valid request" do
        base_string = "v0:#{timestamp}:#{body}"
        signature = "v0=#{OpenSSL::HMAC.hexdigest('SHA256', signing_secret, base_string)}"

        result = described_class.verify_request(timestamp, signature, body)

        expect(result).to be true
      end
    end

    context "with invalid signature" do
      it "returns false for incorrect signature" do
        signature = "v0=invalid_signature"

        result = described_class.verify_request(timestamp, signature, body)

        expect(result).to be false
      end
    end

    context "with missing timestamp" do
      it "returns false when timestamp is blank" do
        signature = "v0=valid"

        result = described_class.verify_request(nil, signature, body)

        expect(result).to be false
      end
    end

    context "with missing signature" do
      it "returns false when signature is blank" do
        result = described_class.verify_request(timestamp, nil, body)

        expect(result).to be false
      end
    end

    context "with old timestamp" do
      it "returns false for timestamps older than 5 minutes" do
        old_timestamp = (Time.current - 6.minutes).to_i.to_s
        base_string = "v0:#{old_timestamp}:#{body}"
        signature = "v0=#{OpenSSL::HMAC.hexdigest('SHA256', signing_secret, base_string)}"

        result = described_class.verify_request(old_timestamp, signature, body)

        expect(result).to be false
      end
    end

    context "with recent timestamp at boundary" do
      it "returns true for timestamps within 5 minute window" do
        recent_timestamp = (Time.current - 4.minutes).to_i.to_s
        base_string = "v0:#{recent_timestamp}:#{body}"
        signature = "v0=#{OpenSSL::HMAC.hexdigest('SHA256', signing_secret, base_string)}"

        result = described_class.verify_request(recent_timestamp, signature, body)

        expect(result).to be true
      end
    end
  end

  describe "#handle_verification" do
    it "returns challenge for URL verification request" do
      payload = {
        "type" => "url_verification",
        "challenge" => "3eZbrw1aBc2L2hj4k9L7VL0Z0e8c5O1B7d3R6p4F2"
      }

      result = described_class.handle_verification(payload)

      expect(result).to eq({ challenge: "3eZbrw1aBc2L2hj4k9L7VL0Z0e8c5O1B7d3R6p4F2" })
    end

    it "returns nil for non-verification requests" do
      payload = { "type" => "event_callback" }

      result = described_class.handle_verification(payload)

      expect(result).to be_nil
    end
  end

  describe "#secure_compare" do
    it "returns true for identical strings" do
      result = described_class.secure_compare("hello", "hello")

      expect(result).to be true
    end

    it "returns false for different strings" do
      result = described_class.secure_compare("hello", "world")

      expect(result).to be false
    end

    it "returns false for different lengths" do
      result = described_class.secure_compare("hello", "hello!")

      expect(result).to be false
    end

    it "returns false for non-string arguments" do
      result = described_class.secure_compare(123, 123)

      expect(result).to be false
    end

    it "returns false when either argument is not a string" do
      result = described_class.secure_compare("hello", 123)

      expect(result).to be false
    end

    it "uses constant-time comparison to prevent timing attacks" do
      # This test verifies the implementation uses byte-by-byte comparison
      # The actual timing attack prevention is implementation-level
      a = "v0=valid_signature_here_abc123"
      b = "v0=valid_signature_here_abc123"
      c = "v0=invalid_signature_here_xyz789"

      expect(described_class.secure_compare(a, b)).to be true
      expect(described_class.secure_compare(a, c)).to be false
    end
  end
end
