# frozen_string_literal: true

require "nokogiri"

# A WordPress export file (WXR: RSS with WordPress's own elements), read into
# plain items. Only what an import needs: pages, posts and attachments, with
# their content, hierarchy, terms, featured image and Yoast SEO. Menus,
# revisions, comments and custom post types are left out.
#
#   export = WordpressImport::Export.new(File.read("site.WordPress.xml"))
#   export.site_url     # "https://example.com"
#   export.pages        # [Item, …] in order, parents before children
#   export.posts
#   export.attachments  # by id: {"12" => Item}
module WordpressImport
  class Export
    class Invalid < StandardError; end

    NAMESPACES = {
      "wp" => %r{wordpress\.org/export/[\d.]+/?\z},
      "content" => %r{purl\.org/rss/1\.0/modules/content},
      "excerpt" => %r{wordpress\.org/export/.*/excerpt},
      "dc" => %r{purl\.org/dc/elements}
    }.freeze

    Item = Data.define(:id, :type, :title, :slug, :status, :link, :parent_id, :menu_order, :content, :excerpt,
      :published_at, :categories, :tags, :meta, :attachment_url) do
      def published? = status == "publish"
      def thumbnail_id = meta["_thumbnail_id"].presence
      def seo_title = meta["_yoast_wpseo_title"].presence
      def seo_description = meta["_yoast_wpseo_metadesc"].presence
      def noindex? = meta["_yoast_wpseo_meta-robots-noindex"] == "1"
    end

    attr_reader :site_url, :title

    def initialize(xml)
      @doc = Nokogiri::XML(xml) { it.recover.nonet }
      channel = @doc.at_xpath("/rss/channel") or raise Invalid, "This isn't a WordPress export: it has no RSS channel."
      @prefixes = prefixes
      raise Invalid, "This isn't a WordPress export: it has no WordPress elements." unless @prefixes["wp"]

      @title = text(channel, "title")
      @site_url = (text(channel, "wp:base_site_url").presence || text(channel, "link")).to_s.chomp("/")
      @items = channel.xpath("item").map { item(it) }
    end

    def pages = by_tree(@items.select { it.type == "page" })
    def posts = @items.select { it.type == "post" }
    def attachments = @items.select { it.type == "attachment" }.index_by(&:id)

    private

    # The prefix each namespace is bound to in this file, whichever version
    # of WXR it is (1.0, 1.1, 1.2).
    def prefixes
      @doc.root.namespaces.each_with_object({}) do |(attribute, uri), found|
        NAMESPACES.each { |name, pattern| found[name] ||= attribute.delete_prefix("xmlns:") if uri.match?(pattern) }
      end
    end

    def item(node)
      meta = node.xpath("#{@prefixes["wp"]}:postmeta").to_h do |row|
        [text(row, "wp:meta_key"), text(row, "wp:meta_value")]
      end
      terms = ->(domain) { node.xpath("category[@domain='#{domain}']").map { it.text.strip }.reject(&:empty?).uniq }

      Item.new(
        id: text(node, "wp:post_id"),
        type: text(node, "wp:post_type"),
        title: text(node, "title"),
        slug: text(node, "wp:post_name"),
        status: text(node, "wp:status"),
        link: text(node, "link"),
        parent_id: text(node, "wp:post_parent").then { (it == "0") ? nil : it.presence },
        menu_order: text(node, "wp:menu_order").to_i,
        content: text(node, "content:encoded"),
        excerpt: text(node, "excerpt:encoded"),
        published_at: time(text(node, "wp:post_date_gmt")) || time(text(node, "wp:post_date")),
        categories: terms.("category"),
        tags: terms.("post_tag"),
        meta: meta,
        attachment_url: text(node, "wp:attachment_url").presence
      )
    end

    # Parents before their children, then by menu order.
    def by_tree(pages)
      ids = pages.map(&:id)
      depth = ->(page, seen = []) { (page.parent_id && ids.include?(page.parent_id) && !seen.include?(page.id)) ? 1 + depth.(pages.find { it.id == page.parent_id }, seen + [page.id]) : 0 }
      pages.sort_by { [depth.(it), it.menu_order, it.id.to_i] }
    end

    def text(node, path)
      prefix, name = path.include?(":") ? path.split(":", 2) : [nil, path]
      selector = prefix ? "#{@prefixes[prefix] || prefix}:#{name}" : name
      node.at_xpath(selector, @doc.root.namespaces)&.text.to_s.strip
    rescue Nokogiri::XML::XPath::SyntaxError
      ""
    end

    def time(value)
      return if value.blank? || value.start_with?("0000")

      Time.find_zone("UTC").parse(value)
    rescue ArgumentError
      nil
    end
  end
end
