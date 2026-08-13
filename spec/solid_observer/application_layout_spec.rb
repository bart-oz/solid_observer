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
        @component = opts.fetch(:component, "home")
        @alerts_component_enabled = opts.fetch(:alerts_component_enabled, false)
        @active_alert_count = opts.fetch(:active_alert_count, 0)
      end

      def csrf_meta_tags
        '<meta name="csrf-param" content="_token"><meta name="csrf-token" content="test">'
      end

      def content_for?(_key)
        false
      end

      def asset_path(path)
        "/assets/#{path}"
      end

      def live_poll_script_path
        "/solid_observer/live_poll.js"
      end

      def link_to(text, url, html_options = {})
        css = html_options[:class]
        aria = html_options[:"aria-current"]
        aria_attr = %( aria-current="#{aria}") if aria
        %(<a href="#{url}"#{" class=\"#{css}\"" if css}#{aria_attr}>#{text}</a>)
      end

      def root_path
        "/solid_observer"
      end

      def queue_dashboard_path
        "/solid_observer/queue"
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

      def cache_dashboard_path
        "/solid_observer/cache"
      end

      def cable_dashboard_path
        "/solid_observer/cable"
      end

      def trace_path(id)
        "/solid_observer/traces/#{id}"
      end

      def alerts_path
        "/solid_observer/alerts"
      end

      def alerts_component_enabled?
        @alerts_component_enabled
      end

      def alerts_nav_label
        (@active_alert_count > 0) ? %(Alerts<span class="so-badge so-badge--pill so-badge--danger">#{@active_alert_count}</span>) : "Alerts"
      end

      def home?
        @controller_name == "dashboard" && @component.to_s == "home"
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

    it "includes sparkline CSS rules for chart strip and spark components" do
      expect(template_source).to include(".so-chart-strip")
      expect(template_source).to include(".so-chart-strip:has(> .so-spark:only-child)")
      expect(template_source).to include(".so-spark")
      expect(template_source).to include(".so-spark__svg")
      expect(template_source).to include(".so-spark__baseline")
      expect(template_source).to include(".so-spark__line")
      expect(template_source).to include(".so-spark__label")
      expect(template_source).to include(".so-spark__value")
    end

    it "includes pill toggle CSS rules for the restyled Live switch" do
      expect(template_source).to include(".so-toggle--pill")
      expect(template_source).to include(".so-toggle__track")
      expect(template_source).to include(".so-toggle__thumb")
      expect(template_source).to include(".so-toggle--on .so-toggle__track")
      expect(template_source).to include(".so-toggle--on .so-toggle__thumb")
      expect(template_source).to include("input:focus-visible + .so-toggle__track")
      expect(template_source).to include(".so-toggle__label")
      expect(template_source).to include(".so-toggle__sep")
      expect(template_source).to include(".so-toggle__cadence")
      expect(template_source).to include(".so-toggle__dot")
      expect(template_source).to include(".so-toggle--on .so-toggle__dot")
    end

    it "includes static 6px success dot for live-on state (no infinite pulse)" do
      expect(template_source).to include(".so-toggle__dot")
      expect(template_source).to include(".so-toggle--on .so-toggle__dot")
      expect(template_source).not_to include("@keyframes so-pulse")
    end

    it "includes prefers-reduced-motion media query for toggle transitions" do
      expect(template_source).to include("@media (prefers-reduced-motion: reduce)")
      expect(template_source).to include("transition: none")
    end

    it "does not use box-shadow inside any .so-toggle CSS rule" do
      # Extract the toggle-related CSS block and assert no box-shadow
      toggle_block = template_source[/\.so-toggle--pill.*?(?=\n\s*\.[a-z]|\n\s+\.so-empty)/m, 0] || ""
      expect(toggle_block).not_to include("box-shadow")
    end

    it "does not include legacy toggle hint rule" do
      expect(template_source).not_to include(".so-toggle__hint")
    end
  end

  describe "rendering" do
    describe "CSRF meta tags" do
      it "includes the csrf-token meta tag" do
        html = render_layout
        expect(html).to include('name="csrf-token"')
      end
    end

    describe "live polling script" do
      it "does not emit a refresh meta tag" do
        expect(render_layout).not_to include('http-equiv="refresh"')
      end

      it "loads the live polling asset script" do
        html = render_layout

        expect(html).to include('src="/solid_observer/live_poll.js"')
        expect(html).to include("defer")
      end

      it "does not include legacy inline polling script content" do
        html = render_layout

        expect(html).not_to include("fetch(location.href")
        expect(html).not_to include("meta.remove()")
      end
    end

    describe "navigation" do
      it "includes Home link in the sidebar" do
        html = render_layout
        expect(html).to include(">Home<")
      end

      it "includes Home, Overview, and Jobs links" do
        html = render_layout(persistence_mode: true)
        expect(html).to include(">Home<")
        expect(html).to include("Overview")
        expect(html).to include("Jobs")
      end

      it "includes Overview and Jobs links in realtime mode" do
        html = render_layout(persistence_mode: false)
        expect(html).to include("Overview")
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

      it "marks Home as active when component is home" do
        html = render_layout(controller_name: "dashboard", component: "home")
        expect(html).to include('class="active"')
        expect(html).to include(">Home</a>")
      end

      it "marks Home with aria-current when component is home" do
        html = render_layout(controller_name: "dashboard", component: "home")
        expect(html).to include('aria-current="page"')
        expect(html).to include(">Home</a>")
      end

      it "does not mark Queue Overview as active when component is home" do
        html = render_layout(controller_name: "dashboard", component: "home")
        overview_link = html[/href="\/solid_observer\/queue"[^>]*>Overview/, 0]
        expect(overview_link).not_to include("active")
      end

      it "marks Queue Overview as active when component is queue" do
        html = render_layout(controller_name: "dashboard", component: "queue")
        expect(html).to include('class="active"')
        expect(html).to include(">Overview</a>")
      end

      it "does not mark Home as active when component is queue" do
        html = render_layout(controller_name: "dashboard", component: "queue")
        home_link = html[/href="\/solid_observer"[^>]*>Home/, 0]
        expect(home_link).not_to include("active")
      end

      it "does not mark any dashboard link active when on jobs controller" do
        html = render_layout(controller_name: "jobs", component: "home")
        home_link = html[/href="\/solid_observer"[^>]*>Home/, 0]
        expect(home_link).not_to include("active")
        overview_link = html[/href="\/solid_observer\/queue"[^>]*>Overview/, 0]
        expect(overview_link).not_to include("active")
      end

      it "omits the Alerts link when alerting is unavailable" do
        html = render_layout(alerts_component_enabled: false, active_alert_count: 3)
        expect(html).not_to include("/solid_observer/alerts")
      end

      it "shows the Alerts link without a badge when nothing is firing" do
        html = render_layout(alerts_component_enabled: true, active_alert_count: 0)
        expect(html).to include('href="/solid_observer/alerts"')
        expect(html).not_to include('<span class="so-badge so-badge--pill so-badge--danger"')
      end

      it "shows a count badge on the Alerts link when alerts are firing" do
        html = render_layout(alerts_component_enabled: true, active_alert_count: 3)
        expect(html).to include('href="/solid_observer/alerts"')
        expect(html).to include('<span class="so-badge so-badge--pill so-badge--danger">3</span>')
      end

      it "marks the Alerts link active on the alerts controller" do
        html = render_layout(controller_name: "alerts", alerts_component_enabled: true)
        alerts_link = html[/href="\/solid_observer\/alerts"[^>]*/, 0]
        expect(alerts_link).to include("active")
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

  describe "confirmation dialog handler" do
    it "includes a data-confirm submit handler script" do
      expect(template_source).to include('querySelector("[data-confirm]")')
    end

    it "shows window.confirm with the message" do
      expect(template_source).to include("window.confirm")
    end

    it "prevents form submission when user cancels" do
      expect(template_source).to include("event.preventDefault()")
    end
  end

  describe "responsive design" do
    it "includes mobile viewport meta tag" do
      expect(template_source).to include('name="viewport"')
      expect(template_source).to include("width=device-width")
    end

    it "includes mobile media query breakpoint" do
      expect(template_source).to include("@media (max-width: 768px)")
    end

    it "makes tables horizontally scrollable on mobile" do
      expect(template_source).to include("overflow-x: auto")
    end

    it "collapses sidebar to single column on mobile" do
      expect(template_source).to include("grid-template-columns: 1fr")
    end
  end
end
