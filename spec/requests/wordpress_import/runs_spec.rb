# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Import from WordPress", type: :request do
  include ActiveJob::TestHelper

  let(:admin) { create(:user) }
  let(:data_dir) { Pathname(Dir.mktmpdir("wordpress-import")) }

  around { |example| with_env("CMS_DATA_DIR" => data_dir.to_s) { example.run } }
  after { data_dir.rmtree }

  before do
    switch_plugin :wordpress_import, on: true
    BlockType::Defaults.install!
    sign_in_as admin
  end

  it "takes the export file and imports it in the background, then shows how it went" do
    get wordpress_import_runs_path
    expect(response.body).to include("Import from WordPress", "Posts go into")

    file = Rack::Test::UploadedFile.new(File.expand_path("../../fixtures/wordpress.xml", __dir__), "text/xml")
    post wordpress_import_runs_path, params: {file: file, collection: "articles", media: "0", redirects: "1", drafts: "1"}
    run = WordpressImport::Run.last
    expect(response).to redirect_to(wordpress_import_run_path(run))

    perform_enqueued_jobs
    expect(run.reload).to have_attributes(status: "succeeded", counts: include("pages" => 2, "posts" => 2))
    expect(Collection.find_by!(slug: "articles").entries.count).to eq(2)
    expect(run.path).not_to exist

    get wordpress_import_run_path(run)
    expect(response.body).to include("wordpress.xml", "succeeded")
  end

  it "says what's wrong with a file that isn't an export" do
    file = Rack::Test::UploadedFile.new(StringIO.new("<html></html>"), "text/xml", original_filename: "page.xml")
    post wordpress_import_runs_path, params: {file: file, media: "1", redirects: "1", drafts: "1"}
    perform_enqueued_jobs

    expect(WordpressImport::Run.last).to have_attributes(status: "failed", log: a_string_matching(/isn't a WordPress export/))
  end
end
