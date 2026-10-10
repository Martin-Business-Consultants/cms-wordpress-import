# frozen_string_literal: true

module WordpressImport
  # Tools › Import from WordPress: the export file and what to bring, and
  # each import with how it went.
  class RunsController < ::ApplicationController
    include PluginGated
    plugin :wordpress_import

    requires_capability "wordpress_import:run"

    def index
      @runs = Run.ordered.includes(:requested_by).limit(10)
      @collections = Collection.order(:name).pluck(:name, :slug)
    end

    def create
      run = Run.start(params[:file], by: Current.user, collection: params[:collection],
        media: params[:media] == "1", redirects: params[:redirects] == "1", drafts: params[:drafts] == "1")
      redirect_to wordpress_import_run_path(run)
    rescue Run::Refused => error
      redirect_to wordpress_import_runs_path, alert: error.message
    end

    def show
      @run = Run.find(params[:id])
    end
  end
end
