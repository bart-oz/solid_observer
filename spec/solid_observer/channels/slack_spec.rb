# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::Channels::Slack do
  after { SolidObserver.reset_configuration! }

  let(:payload) do
    {
      rule_name: "High error rate",
      severity: "critical",
      metric_type: "error_rate",
      metric_value: 0.42,
      environment: "production",
      event_type: "triggered",
      deep_link_url: "https://app.example.com/solid_observer"
    }
  end

  def stub_http(status_body:, code: "200")
    response = instance_double(Net::HTTPOK, value: nil, body: status_body, code: code)
    http = instance_double(Net::HTTP, "use_ssl=": nil, "open_timeout=": nil, "read_timeout=": nil, request: response)
    allow(Net::HTTP).to receive(:new).and_return(http)
    response
  end

  before { SolidObserver.config.slack_webhook_url = "https://hooks.slack.com/services/T000/B000/XXX" }

  it "posts the payload as a Slack-formatted JSON message" do
    stub_http(status_body: '{"ok":true}')

    described_class.new.deliver(double, payload)

    expect(Net::HTTP).to have_received(:new).with("hooks.slack.com", 443)
  end

  it "does not raise when the response body reports ok: true" do
    stub_http(status_body: '{"ok":true}')

    expect { described_class.new.deliver(double, payload) }.not_to raise_error
  end

  it "raises Net::HTTPClientException when the Slack body reports ok: false" do
    stub_http(status_body: '{"ok":false,"error":"invalid_token"}')

    expect { described_class.new.deliver(double, payload) }.to raise_error(Net::HTTPClientException, /invalid_token/)
  end

  it "tolerates a non-JSON response body (classic incoming-webhook plain text)" do
    stub_http(status_body: "ok")

    expect { described_class.new.deliver(double, payload) }.not_to raise_error
  end

  it "raises Net::HTTPClientException for a 4xx HTTP status via response.value" do
    response = Net::HTTPBadRequest.new("1.1", "400", "Bad Request")
    def response.value
      raise Net::HTTPClientException.new("400 Bad Request", self)
    end
    http = instance_double(Net::HTTP, "use_ssl=": nil, "open_timeout=": nil, "read_timeout=": nil, request: response)
    allow(Net::HTTP).to receive(:new).and_return(http)

    expect { described_class.new.deliver(double, payload) }.to raise_error(Net::HTTPClientException)
  end
end
