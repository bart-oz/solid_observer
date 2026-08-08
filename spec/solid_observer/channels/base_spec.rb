# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::Channels::Base do
  describe "#deliver" do
    it "raises NotImplementedError" do
      expect { described_class.new.deliver(double, {}) }.to raise_error(NotImplementedError, /must implement #deliver/)
    end
  end

  describe "#post_json (via a minimal subclass)" do
    let(:subclass) do
      Class.new(described_class) do
        def call(url, body)
          post_json(url, body)
        end
      end
    end

    it "sets 5s open/read timeouts and posts the given JSON body" do
      http = instance_double(Net::HTTP, "use_ssl=": nil, "open_timeout=": nil, "read_timeout=": nil)
      response = instance_double(Net::HTTPOK, value: nil)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:request).and_return(response)

      expect(http).to receive(:open_timeout=).with(5)
      expect(http).to receive(:read_timeout=).with(5)

      result = subclass.new.call("https://example.com/hook", '{"ok":true}')

      expect(result).to eq(response)
    end

    it "raises Net::HTTPClientException for a 4xx response via response.value" do
      response = Net::HTTPBadRequest.new("1.1", "400", "Bad Request")
      def response.value
        raise Net::HTTPClientException.new("400 Bad Request", self)
      end
      http = instance_double(Net::HTTP, "use_ssl=": nil, "open_timeout=": nil, "read_timeout=": nil, request: response)
      allow(Net::HTTP).to receive(:new).and_return(http)

      expect { subclass.new.call("https://example.com/hook", "{}") }.to raise_error(Net::HTTPClientException)
    end

    it "raises Net::HTTPFatalError for a 5xx response via response.value" do
      response = Net::HTTPInternalServerError.new("1.1", "500", "Internal Server Error")
      def response.value
        raise Net::HTTPFatalError.new("500 Internal Server Error", self)
      end
      http = instance_double(Net::HTTP, "use_ssl=": nil, "open_timeout=": nil, "read_timeout=": nil, request: response)
      allow(Net::HTTP).to receive(:new).and_return(http)

      expect { subclass.new.call("https://example.com/hook", "{}") }.to raise_error(Net::HTTPFatalError)
    end
  end
end
