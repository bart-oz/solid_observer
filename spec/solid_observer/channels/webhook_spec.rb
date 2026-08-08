# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::Channels::Webhook do
  after { SolidObserver.reset_configuration! }

  let(:payload) do
    {rule_name: "High error rate", severity: "critical", metric_type: "error_rate", metric_value: 0.42, event_type: "triggered"}
  end

  let(:captured_request) { nil }

  def stub_http(code: "200")
    response = instance_double(Net::HTTPOK, value: nil, code: code)
    http = instance_double(Net::HTTP, "use_ssl=": nil, "open_timeout=": nil, "read_timeout=": nil)
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:request) do |request|
      @sent_request = request
      response
    end
    response
  end

  before { SolidObserver.config.webhook_endpoint_url = "https://example.com/hooks/solid_observer" }

  it "POSTs the payload as JSON" do
    stub_http

    described_class.new.deliver(double, payload)

    expect(@sent_request.body).to eq(payload.to_json)
    expect(@sent_request["Content-Type"]).to eq("application/json")
  end

  context "when webhook_secret is present" do
    before { SolidObserver.config.webhook_secret = "s3cr3t" }

    it "signs the JSON body with an HMAC-SHA256 hex digest header" do
      stub_http

      described_class.new.deliver(double, payload)

      expected = OpenSSL::HMAC.hexdigest("SHA256", "s3cr3t", payload.to_json)
      expect(@sent_request["X-Solid-Observer-Signature"]).to eq(expected)
    end
  end

  context "when webhook_secret is absent" do
    it "sends no signature header" do
      stub_http

      described_class.new.deliver(double, payload)

      expect(@sent_request["X-Solid-Observer-Signature"]).to be_nil
    end
  end

  it "raises Net::HTTPFatalError for a 5xx response via response.value" do
    response = Net::HTTPInternalServerError.new("1.1", "500", "Internal Server Error")
    def response.value
      raise Net::HTTPFatalError.new("500 Internal Server Error", self)
    end
    http = instance_double(Net::HTTP, "use_ssl=": nil, "open_timeout=": nil, "read_timeout=": nil, request: response)
    allow(Net::HTTP).to receive(:new).and_return(http)

    expect { described_class.new.deliver(double, payload) }.to raise_error(Net::HTTPFatalError)
  end
end
