# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::Paginatable do
  let(:host_class) do
    Class.new do
      include SolidObserver::Paginatable
    end
  end
  let(:host) { host_class.new }
  let(:scope) { double("scope", count: 60) }

  describe "#paginate_scope" do
    before { host.instance_variable_set(:@page, 2) }

    it "sets @total_count from scope.count" do
      host.send(:paginate_scope, scope, per_page: 25)
      expect(host.instance_variable_get(:@total_count)).to eq(60)
    end

    it "sets @total_pages based on count and per_page" do
      host.send(:paginate_scope, scope, per_page: 25)
      expect(host.instance_variable_get(:@total_pages)).to eq(3)
    end

    it "returns the correct offset for page 2" do
      offset = host.send(:paginate_scope, scope, per_page: 25)
      expect(offset).to eq(25)
    end

    it "returns offset 0 for page 1" do
      host.instance_variable_set(:@page, 1)
      offset = host.send(:paginate_scope, scope, per_page: 25)
      expect(offset).to eq(0)
    end

    it "sets @page to 1 when below 1" do
      host.instance_variable_set(:@page, 0)
      host.send(:paginate_scope, scope, per_page: 25)
      expect(host.instance_variable_get(:@page)).to eq(1)
    end

    it "sets @page to 1 when above total_pages" do
      host.instance_variable_set(:@page, 10)
      host.send(:paginate_scope, scope, per_page: 25)
      expect(host.instance_variable_get(:@page)).to eq(1)
    end

    it "does not change @page when within valid range" do
      host.instance_variable_set(:@page, 2)
      host.send(:paginate_scope, scope, per_page: 25)
      expect(host.instance_variable_get(:@page)).to eq(2)
    end

    it "does not clamp when total_pages is 0" do
      host.instance_variable_set(:@page, 1)
      zero_scope = double("zero_scope", count: 0)
      host.send(:paginate_scope, zero_scope, per_page: 25)
      expect(host.instance_variable_get(:@page)).to eq(1)
    end
  end
end
