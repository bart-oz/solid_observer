# frozen_string_literal: true

require "spec_helper"
require "erb"

RSpec.describe "SolidObserver application layout" do
  after { SolidObserver.reset_configuration! }

  let(:template_path) do
    File.expand_path("../../app/views/layouts/solid_observer/application.html.erb", __dir__)
  end

  let(:template_source) { File.read(template_path) }

  # Minimal context that provides every method called from the layout.
  # SolidObserver.config is called directly on the module, so we set it
  # via SolidObserver.config in each example (or in a before block).
  let(:context_class) do
    Class.new do
      attr_reader :flash, :controller_name

      def initialize(opts = {})
        @persistence_mode = opts.fetch(:persistence_mode, true)
        @flash = opts.fetch(:flash, {})
        @controller_name = opts.fetch(:controller_name, "dashboard")
      end

      def csrf_meta_tags
        '<meta name="csrf-param" content="_token"><meta name="csrf-token" content="test">'
      end

      def content_for?(_key)
        false
      end

      def link_to(text, url, html_options = {})
        css = html_options[:class]
        %(<a href="#{url}"#{" class=\"#{css}\"" if css}>#{text}</a>)
      end

      def root_path
        "/solid_observer"
      end

      def jobs_path
        "/solid_observer/jobs"
      end

      def events_path
        "/solid_observer/events"
      end

      def storage_path
        "/solid_observer/storage"
      end

      def persistence_mode?
        @persistence_mode
      end

      def get_binding
        binding
      end
    end
  end

  def render_layout(opts = {})
    source = template_source.gsub("<%= yield %>", "CONTENT_PLACEHOLDER")
    context = context_class.new(opts)
    ERB.new(source).result(context.get_binding)
  end

  describe "static structure" do
    it "starts with a DOCTYPE declaration" do
      expect(template_source).to start_with("<!DOCTYPE html>")
    end

    it "has a UTF-8 charset meta tag" do
      expect(template_source).to include('<meta charset="utf-8">')
    end

    it "has a responsive viewport meta tag" do
      expect(template_source).to include("viewport")
      expect(template_source).to include("width=device-width")
    end

    it "calls csrf_meta_tags" do
      expect(template_source).to include("csrf_meta_tags")
    end

    it "embeds all CSS in a single style block" do
      expect(template_source).to include("<style>")
      expect(template_source).not_to match(/<link[^>]+stylesheet/i)
    end

    it "defines CSS custom properties in :root" do
      expect(template_source).to include(":root {")
      expect(template_source).to include("--so-sidebar-width:")
      expect(template_source).to include("--so-bg:")
    end

    it "uses CSS Grid for the two-column layout" do
      expect(template_source).to include("display: grid")
      expect(template_source).to include("grid-template-columns")
    end

    it "has sidebar and main content regions" do
      expect(template_source).to include("so-sidebar")
      expect(template_source).to include("so-content")
    end

    it "yields page content" do
      expect(template_source).to include("<%= yield %>")
    end

    it "has flash markup for notice and alert" do
      expect(template_source).to include("flash[:notice]")
      expect(template_source).to include("flash[:alert]")
      expect(template_source).to include("so-flash--notice")
      expect(template_source).to include("so-flash--alert")
    end

    it "has a mode indicator driven by persistence_mode?" do
      expect(template_source).to include("so-sidebar__mode")
      expect(template_source).to include("persistence_mode?")
    end

    it "gates Events and Storage links on persistence_mode?" do
      expect(template_source).to include("if persistence_mode?")
      expect(template_source).to include("events_path")
      expect(template_source).to include("storage_path")
    end
  end

  describe "rendering" do
    describe "CSRF meta tags" do
      it "includes the csrf-token meta tag" do
        html = render_layout
        expect(html).to include('name="csrf-token"')
      end
    end

    describe "auto-refresh" do
      it "does not emit a refresh meta tag when ui_refresh_interval is 0" do
        SolidObserver.config.ui_refresh_interval = 0
        expect(render_layout).not_to include('http-equiv="refresh"')
      end

      it "emits a refresh meta tag when ui_refresh_interval is greater than 0" do
        SolidObserver.config.ui_refresh_interval = 30
        html = render_layout
        expect(html).to include('http-equiv="refresh"')
        expect(html).to include('content="30"')
      end
    end

    describe "navigation" do
      it "includes Dashboard and Jobs links in persistence mode" do
        html = render_layout(persistence_mode: true)
        expect(html).to include("Dashboard")
        expect(html).to include("Jobs")
      end

      it "includes Dashboard and Jobs links in realtime mode" do
        html = render_layout(persistence_mode: false)
        expect(html).to include("Dashboard")
        expect(html).to include("Jobs")
      end

      it "shows Events and Storage links in persistence mode" do
        html = render_layout(persistence_mode: true)
        expect(html).to include("Events")
        expect(html).to include("Storage")
      end

      it "hides Events and Storage links in realtime mode" do
        html = render_layout(persistence_mode: false)
        expect(html).not_to include("Events")
        expect(html).not_to include("Storage")
      end

      it "marks the active controller's link with class active" do
        html = render_layout(controller_name: "dashboard")
        expect(html).to include('class="active">Dashboard')
      end

      it "does not mark a different controller's link as active" do
        html = render_layout(controller_name: "jobs")
        expect(html).not_to include('class="active">Dashboard')
      end
    end

    describe "mode indicator" do
      it "shows Persistence in persistence mode" do
        html = render_layout(persistence_mode: true)
        expect(html).to include("Mode: Persistence")
      end

      it "shows Real-time in realtime mode" do
        html = render_layout(persistence_mode: false)
        expect(html).to include("Mode: Real-time")
      end
    end

    describe "flash messages" do
      it "renders a notice message" do
        html = render_layout(flash: {notice: "Job enqueued successfully"})
        expect(html).to include("so-flash--notice")
        expect(html).to include("Job enqueued successfully")
      end

      it "renders an alert message" do
        html = render_layout(flash: {alert: "Something went wrong"})
        expect(html).to include("so-flash--alert")
        expect(html).to include("Something went wrong")
      end

      it "renders no flash elements when flash is empty" do
        html = render_layout(flash: {})
        expect(html).not_to include('class="so-flash so-flash--notice"')
        expect(html).not_to include('class="so-flash so-flash--alert"')
      end
    end

    describe "page content" do
      it "renders a yield slot for page-specific content" do
        expect(render_layout).to include("CONTENT_PLACEHOLDER")
      end
    end
  end
end
