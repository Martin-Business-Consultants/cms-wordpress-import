# frozen_string_literal: true

require "wordpress_import/version"
require "wordpress_import/engine"

# WordPress Import: a WordPress export file (Tools › Export in WordPress, a
# WXR .xml) becomes this install's pages, posts, media and redirects. Pages
# keep their hierarchy, posts go into a collection, images are downloaded
# into the media library and their addresses in the content rewritten, Yoast
# SEO titles and descriptions come along, and every old address that changes
# redirects to the new one. Running it again updates what it imported before.
module WordpressImport
end
