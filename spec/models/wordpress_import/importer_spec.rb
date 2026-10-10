# frozen_string_literal: true

require "rails_helper"

RSpec.describe WordpressImport::Importer do
  let(:export) { WordpressImport::Export.new(File.read(File.expand_path("../../fixtures/wordpress.xml", __dir__))) }
  let(:image) { File.binread(File.expand_path("../../fixtures/garden-bed.png", __dir__)) }
  let(:fetched) { [] }
  let(:fetch) { ->(url) { fetched << url; [StringIO.new(image), "image/png"] } }

  before { BlockType::Defaults.install! }

  def import(**options) = described_class.new(export, fetch: fetch, **options).call

  it "brings pages under their parents, posts into a collection, images into the library, and redirects" do
    importer = import

    services = Page.find_by!(slug: "services", parent_id: nil)
    fall = Page.find_by!(slug: "fall-planting", parent: services)
    post = Collection.find_by!(slug: "posts").entries.find_by!(slug: "raised-beds")
    asset = Asset.find_by!(folder: "/wordpress", name: "garden-bed")
    image_path = Rails.application.routes.url_helpers.rails_blob_path(asset.file, only_path: true)

    expect(importer.counts).to include("media" => 1, "pages" => 2, "posts" => 2)
    expect(services).to have_attributes(status: "published", title: "Services")
    expect(services.seo).to include("meta_title" => "Garden services | Green Thumb", "meta_description" => "Design, planting and care.")
    expect(services.blocks.first.dig("data", "body")).to eq("<p>What we do, season by season.</p>")

    body = fall.blocks.first.dig("data", "body")
    expect(body).to start_with("<p>Bulbs go in before the frost.</p>")
    expect(body).to include(%(src="#{image_path}"), %(href="#{post.public_path}"))

    expect(post).to have_attributes(title: "Raised beds & why they work", status: "published", published_at: Time.utc(2025, 4, 2, 8, 30))
    expect(post.frontmatter).to include("excerpt" => "Why we build them.", "categories" => ["How-to"], "tags" => ["soil"],
      "featured_image" => asset.id.to_s)
    expect(asset.alt).to eq("Raised beds in spring")

    draft = Collection.find_by!(slug: "posts").entries.find_by!(slug: "winter-notes")
    expect(draft.status).to eq("draft")

    expect(Redirect.find_by!(source_path: "/2025/04/raised-beds").destination_url).to eq(post.public_path)
    expect(Redirect.where(source_path: "/services")).to be_empty # the same address
  end

  it "updates what it brought before, and reuses its images, when it runs again" do
    import
    again = import

    expect(again.counts).to include("media_reused" => 1, "pages_updated" => 2, "posts_updated" => 2)
    expect(fetched.size).to eq(1)
    expect(Page.where(slug: "services").count).to eq(1)
  end

  it "leaves drafts, media and redirects out when asked" do
    import(drafts: false, media: false, redirects: false)

    expect(Collection.find_by!(slug: "posts").entries.pluck(:slug)).to eq(["raised-beds"])
    expect(Asset.where(folder: "/wordpress")).to be_empty
    expect(Redirect.count).to eq(0)
  end

  it "notes an image it couldn't download and carries on" do
    importer = described_class.new(export, fetch: ->(_) { raise "the server answered 404" }).call

    expect(importer.counts).to include("media_failed" => 1, "pages" => 2)
    expect(importer.log).to include(a_string_matching(/garden-bed\.jpg over: the server answered 404/))
  end
end
