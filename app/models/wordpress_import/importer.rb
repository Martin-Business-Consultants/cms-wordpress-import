# frozen_string_literal: true

require "net/http"

# Writes a WordPress export (Export) into this install, in four steps:
#
#   media      every attachment, downloaded into the /wordpress folder of the
#              media library (one already there by that name is reused)
#   pages      each page, under its parent, its content one Text block
#   posts      each post, an entry of the posts collection (made, or given
#              the fields it lacks): excerpt, categories, tags, featured image
#   redirects  each old address that changed, to the new one
#
# Content keeps WordPress's HTML (a Text block's Markdown takes HTML, and the
# website sanitizes it), with the editor's block comments taken out,
# paragraphs made from blank lines as WordPress does, and every image or
# link to the old site pointed at what was imported. A page or entry found
# by its slug is updated rather than made again, so a second run is safe.
module WordpressImport
  class Importer
    FOLDER = "/wordpress"
    MAX_DOWNLOAD = 50.megabytes
    BLOCK_TAGS = %w[address article aside blockquote details dialog div dl fieldset figcaption figure footer form
      h1 h2 h3 h4 h5 h6 header hr li main nav ol p pre section table ul].freeze

    POST_FIELDS = [
      {"name" => "excerpt", "label" => "Excerpt", "type" => "text"},
      {"name" => "featured_image", "label" => "Featured image", "type" => "asset"},
      {"name" => "categories", "label" => "Categories", "type" => "string_list"},
      {"name" => "tags", "label" => "Tags", "type" => "string_list"}
    ].freeze

    attr_reader :counts, :log

    # fetch: how a file is downloaded, ->(url) { [io, content_type] } (a test
    # stands one in).
    def initialize(export, collection: "posts", media: true, redirects: true, drafts: true, fetch: nil, logger: nil)
      @export = export
      @collection_slug = collection.to_s.parameterize.presence || "posts"
      @media, @redirects, @drafts = media, redirects, drafts
      @fetch = fetch || method(:download)
      @logger = logger
      @counts = Hash.new(0)
      @log = []
      @assets = {}      # attachment id => Asset
      @urls = {}        # an old file's address (any size) => its new path
      @addresses = {}   # an old page's or post's path => its new path
    end

    def call
      import_media if @media
      pages = import_pages
      posts = import_posts
      # Links between pages and posts point at the new addresses once every one is known.
      (pages + posts).each { relink(it) }
      add_redirects if @redirects
      self
    end

    private

    # --- media ---------------------------------------------------------------

    def import_media
      @export.attachments.each_value do |item|
        url = item.attachment_url or next
        asset = existing_asset(url) || upload(item, url)
        next unless asset

        @assets[item.id] = asset
        path = Rails.application.routes.url_helpers.rails_blob_path(asset.file, only_path: true)
        @urls[url] = path
        @urls[url.sub(/\Ahttps?:/, "")] = path
      end
    end

    def existing_asset(url)
      Asset.find_by(folder: FOLDER, name: asset_name(url)).tap { count(:media_reused) if it }
    end

    def upload(item, url)
      io, content_type = @fetch.call(url)
      asset = Asset.upload!({io: io, filename: File.basename(URI(url).path), content_type: content_type},
        folder: FOLDER, name: asset_name(url), alt: item.meta["_wp_attachment_image_alt"].presence || item.title.presence)
      count(:media)
      asset
    rescue StandardError => error
      note "Couldn't bring #{url} over: #{error.message}"
      count(:media_failed)
      nil
    end

    def asset_name(url) = File.basename(URI(url).path, ".*")

    def download(url, redirects: 3)
      uri = URI(url)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 60) do |http|
        http.request(Net::HTTP::Get.new(uri, "User-Agent" => "Libre Publish WordPress Import"))
      end
      case response
      when Net::HTTPRedirection
        raise "too many redirects" if redirects.zero?

        download(URI.join(url, response["location"]).to_s, redirects: redirects - 1)
      when Net::HTTPSuccess
        raise "it's bigger than #{MAX_DOWNLOAD / 1.megabyte}MB" if response.body.bytesize > MAX_DOWNLOAD

        [StringIO.new(response.body), response.content_type]
      else
        raise "the server answered #{response.code}"
      end
    end

    # --- pages ---------------------------------------------------------------

    def import_pages
      by_id = {}
      @export.pages.filter_map do |item|
        next unless wanted?(item)

        parent = by_id[item.parent_id]
        page = Page.find_or_initialize_by(parent_id: parent&.id, slug: slug_for(item))
        created = page.new_record?
        page.assign_attributes(title: title_for(item), status: status_for(item), locale: page.locale.presence || "en",
          blocks: [text_block(item.content)], seo: seo_for(item, page.seo))
        page.published_at ||= item.published_at if page.respond_to?(:published_at=)
        save(page, item, created ? :pages : :pages_updated) or next
        by_id[item.id] = page
        remember_address(item, page)
        [page, item]
      end
    end

    # --- posts ---------------------------------------------------------------

    def import_posts
      return [] if @export.posts.none?

      collection = posts_collection
      @export.posts.filter_map do |item|
        next unless wanted?(item)

        entry = collection.entries.find_or_initialize_by(slug: slug_for(item))
        created = entry.new_record?
        entry.assign_attributes(title: title_for(item), status: status_for(item), locale: entry.locale.presence || "en",
          body_markdown: content_for(item.content), seo: seo_for(item, entry.seo),
          frontmatter: entry.frontmatter.to_h.merge(
            "excerpt" => item.excerpt.presence, "categories" => item.categories, "tags" => item.tags,
            "featured_image" => @assets[item.thumbnail_id]&.id&.to_s
          ).compact)
        entry.published_at ||= item.published_at
        save(entry, item, created ? :posts : :posts_updated) or next
        remember_address(item, entry)
        [entry, item]
      end
    end

    def posts_collection
      collection = Collection.find_or_initialize_by(slug: @collection_slug)
      collection.name = @collection_slug.titleize if collection.new_record?
      fields = Array(collection.schema&.dig("fields"))
      missing = POST_FIELDS.reject { |field| fields.any? { it["name"] == field["name"] } }
      collection.schema = (collection.schema || {}).merge("fields" => fields + missing) if missing.any? || collection.new_record?
      collection.save!
      note "Made the #{@collection_slug} collection for the posts." if collection.previously_new_record?
      collection
    end

    # --- redirects -------------------------------------------------------------

    def add_redirects
      @addresses.each do |old, new|
        next if old == new || old == "/" || Redirect.exists?(source_path: old)

        Redirect.create!(source_path: old, destination_url: new, status_code: 301, notes: "WordPress import")
        count(:redirects)
      rescue ActiveRecord::RecordInvalid => error
        note "No redirect from #{old}: #{error.message}"
      end
    end

    # --- the content -----------------------------------------------------------

    def text_block(html) = {"type" => "text", "version" => 1, "data" => {"body" => content_for(html)}}

    def content_for(html)
      html = html.to_s.gsub(/<!--\s*\/?wp:.*?-->\n?/m, "")
      html = paragraphs(html) unless html.match?(/<p[\s>]/i)
      rewrite_files(html).strip
    end

    # WordPress's wpautop, simply: text between blank lines that isn't a
    # block element becomes a paragraph, and a lone line break a <br>.
    def paragraphs(html)
      html.split(/\n\s*\n/).map(&:strip).reject(&:empty?).map do |chunk|
        chunk.match?(/\A<(#{BLOCK_TAGS.join("|")})[\s>\/]/i) ? chunk : "<p>#{chunk.gsub(/\s*\n\s*/, "<br>\n")}</p>"
      end.join("\n\n")
    end

    # An image's address, at any of the sizes WordPress made of it
    # (photo-300x200.jpg), becomes its asset's.
    def rewrite_files(html)
      @urls.each do |old, new|
        base = Regexp.escape(old.sub(/\.\w+\z/, ""))
        ext = Regexp.escape(old[/\.\w+\z/].to_s)
        html = html.gsub(/(?:https?:)?#{base.sub(/\A(?:https?:)/, "")}(?:-\d+x\d+)?#{ext}/, new)
      end
      html
    end

    def relink((record, _item))
      field = record.is_a?(Page) ? nil : :body_markdown
      site = Regexp.escape(@export.site_url.sub(/\Ahttps?:/, ""))
      relink = ->(html) {
        html.to_s.gsub(/href="(?:https?:)?#{site}(\/[^"#?]*)([^"]*)"/) do
          path = normalize($1)
          @addresses[path] ? %(href="#{@addresses[path]}#{$2}") : $&
        end
      }
      if field
        changed = relink.(record.body_markdown)
        record.update_columns(body_markdown: changed) if changed != record.body_markdown
      else
        blocks = record.blocks.map { it["type"] == "text" ? it.deep_merge("data" => {"body" => relink.(it.dig("data", "body"))}) : it }
        record.update_columns(blocks: blocks) if blocks != record.blocks
      end
    end

    def remember_address(item, record)
      old = item.link.presence && normalize(URI(item.link).path)
      @addresses[old] = record.public_path if old
    rescue URI::InvalidURIError
      nil
    end

    def normalize(path) = "/#{path.to_s.delete_prefix("/").chomp("/")}"

    # --- each record -----------------------------------------------------------

    def wanted?(item)
      return true if item.published?
      return false unless @drafts && %w[draft pending private future].include?(item.status)

      true
    end

    def slug_for(item)
      slug = (item.slug.presence || item.title.presence || "untitled-#{item.id}").then { CGI.unescape(it) }.parameterize
      slug.match?(Page::SLUG_FORMAT) ? slug : "page-#{item.id}"
    end

    def title_for(item) = CGI.unescapeHTML(item.title.presence || item.slug.presence || "Untitled")

    def status_for(item) = item.published? ? "published" : "draft"

    def seo_for(item, current)
      seo = current.to_h.dup
      seo["meta_title"] = item.seo_title if item.seo_title && !item.seo_title.include?("%%")
      seo["meta_description"] = item.seo_description if item.seo_description
      seo["noindex"] = true if item.noindex?
      seo["og_image_id"] = @assets[item.thumbnail_id].id.to_s if @assets[item.thumbnail_id]
      seo
    end

    def save(record, item, counter)
      record.save!
      count(counter)
      true
    rescue ActiveRecord::RecordInvalid => error
      note "Skipped #{item.type} “#{item.title}”: #{error.record.errors.full_messages.to_sentence}"
      count(:skipped)
      false
    end

    def count(key) = @counts[key.to_s] += 1

    def note(message)
      @log << message
      @logger&.call(message)
    end
  end
end
