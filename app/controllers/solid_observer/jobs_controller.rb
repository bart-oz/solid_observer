# frozen_string_literal: true

module SolidObserver
  class JobsController < ApplicationController
    def index
    end

    def show
    end

    def retry
      redirect_to jobs_path
    end

    def discard
      redirect_to jobs_path
    end
  end
end
