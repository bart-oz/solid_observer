# frozen_string_literal: true

module SolidObserver
  # QueueMetric provides time-series metrics storage for queue statistics.
  #
  # NOTE: Metrics functionality is planned for v0.2.0. This class currently
  # serves as a placeholder and inherits base functionality from BaseMetric.
  # The database connection will be configured by the Engine when metrics
  # are fully implemented.
  #
  # @see BaseMetric for available methods (increment, record)
  class QueueMetric < BaseMetric
  end
end
