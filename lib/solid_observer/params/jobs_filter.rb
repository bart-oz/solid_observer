# frozen_string_literal: true

module SolidObserver
  module Params
    class JobsFilter
      ALLOWED_STATUSES = %w[ready scheduled claimed failed].freeze

      def self.from_params(params)
        new(
          status: params[:status].presence || "ready",
          queue_name: params[:queue_name].presence,
          job_class: params[:job_class].presence,
          page: (params[:page].presence || 1).to_i
        )
      end

      attr_reader :status, :queue_name, :job_class, :page

      def initialize(status:, queue_name:, job_class:, page:)
        @status = normalize_status(status)
        @queue_name = queue_name
        @job_class = job_class
        @page = page
      end

      private

      def normalize_status(status)
        normalized = status.to_s.downcase
        ALLOWED_STATUSES.include?(normalized) ? normalized : "ready"
      end
    end
  end
end
