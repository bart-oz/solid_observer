# frozen_string_literal: true

module SolidObserver
  module Params
    class EventsFilter
      def self.from_params(params)
        new(
          event_type: params[:event_type].presence,
          job_class: params[:job_class].presence,
          queue_name: params[:queue_name].presence,
          from: parse_date(params[:from]),
          to: parse_date(params[:to]),
          page: (params[:page].presence || 1).to_i
        )
      end

      class << self
        private

        def parse_date(date_string)
          return nil if date_string.blank?

          Date.parse(date_string)
        rescue ArgumentError
          nil
        end
      end

      attr_reader :event_type, :job_class, :queue_name, :from, :to, :page

      def initialize(event_type:, job_class:, queue_name:, from:, to:, page:)
        @event_type = event_type
        @job_class = job_class
        @queue_name = queue_name
        @from = from
        @to = to
        @page = page
      end
    end
  end
end
