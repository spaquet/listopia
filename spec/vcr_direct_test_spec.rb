# spec/vcr_direct_test_spec.rb
require 'rails_helper'
require 'net/http'

RSpec.describe "Direct HTTP Test", vcr: { cassette_name: 'direct_http_test' } do
  it "records a direct HTTP request" do
    uri = URI('https://httpbin.org/get')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    request = Net::HTTP::Get.new(uri.path)

    response = http.request(request)
    expect(response.code).to eq('200')
  end
end
