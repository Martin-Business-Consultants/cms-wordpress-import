# frozen_string_literal: true

require_relative "lib/wordpress_import/version"

# The gemspec's name is the plugin's key.
Gem::Specification.new do |spec|
  spec.name = "wordpress_import"
  spec.version = WordpressImport::VERSION
  spec.summary = "WordPress Import: bring a WordPress site's pages, posts and media into Libre Publish"
  spec.authors = ["Martin Business Consultants"]
  spec.homepage = "https://github.com/Martin-Business-Consultants/cms-wordpress-import"
  spec.license = "FSL-1.1-MIT"
  spec.files = Dir["{app,config,db,lib}/**/*"]
  spec.required_ruby_version = ">= 3.3"
  spec.add_dependency "rails", ">= 8.1"
end
