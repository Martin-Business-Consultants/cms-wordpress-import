# frozen_string_literal: true

module WordpressImport
  class ImportJob < ApplicationJob
    queue_as :default

    def perform(run) = run.import_now
  end
end
