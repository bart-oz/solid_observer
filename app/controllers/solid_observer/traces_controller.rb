# frozen_string_literal: true

require_relative "../../helpers/solid_observer/application_helper"

module SolidObserver
  class TracesController < ApplicationController
    helper SolidObserver::ApplicationHelper

    include RequirePersistenceMode

    def show
      result = SolidObserver::Queries::TraceQuery.new.call(correlation_id: params[:id])
      @rows = result.rows
      @unavailable_components = result.unavailable_components
    end
  end
end
