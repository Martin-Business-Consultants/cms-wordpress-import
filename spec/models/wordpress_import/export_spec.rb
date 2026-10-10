# frozen_string_literal: true

require "rails_helper"

RSpec.describe WordpressImport::Export do
  let(:export) { described_class.new(File.read(File.expand_path("../../fixtures/wordpress.xml", __dir__))) }

  it "reads the site, its pages (parents first), posts and attachments" do
    expect(export.site_url).to eq("https://greenthumb.example")
    expect(export.pages.map(&:slug)).to eq(%w[services fall-planting])
    expect(export.posts.map(&:id)).to eq(%w[20 21])
    expect(export.attachments.keys).to eq(["10"])
  end

  it "reads a post's terms, featured image, dates and SEO" do
    post = export.posts.first
    page = export.pages.first

    expect(post).to have_attributes(categories: ["How-to"], tags: ["soil"], thumbnail_id: "10", excerpt: "Why we build them.",
      published_at: Time.utc(2025, 4, 2, 8, 30))
    expect(page).to have_attributes(seo_title: "Garden services | Green Thumb", seo_description: "Design, planting and care.")
  end

  it "refuses a file that isn't a WordPress export" do
    expect { described_class.new("<rss><channel></channel></rss>") }.to raise_error(described_class::Invalid, /WordPress elements/)
    expect { described_class.new("not xml") }.to raise_error(described_class::Invalid)
  end
end
