# frozen_string_literal: true

module SolidObserver
  class StoragesController < ApplicationController
    before_action :require_persistence_mode

    def show
    end
  end
end
