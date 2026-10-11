# frozen_string_literal: true

module WordpressImport
  # A CMS plugin (docs/plugins.md in the core). Its one table,
  # wordpress_import_runs, records each import and how it went.
  class Engine < ::Rails::Engine
    initializer "wordpress_import.migrations" do |app|
      config.paths["db/migrate"].expanded.each { |path| app.config.paths["db/migrate"] << path }
    end

    initializer "wordpress_import.routes" do |app|
      app.routes.append do
        admin = proc do
          scope "wordpress_import", module: "wordpress_import", as: "wordpress_import" do
            resources :runs, only: [:index, :create, :show]
          end
        end
        defined?(Cms::PATH) ? scope(path: Cms::PATH, &admin) : admin.call
      end
    end

    config.to_prepare do
      Cms::Plugins.register :wordpress_import, name: "WordPress Import", version: WordpressImport::VERSION,
        author: "Martin Business Consultants", requires: ">= 1.30",
        homepage: "https://github.com/Martin-Business-Consultants/cms-wordpress-import",
        description: "Bring a WordPress site over from its export file: pages with their hierarchy, posts into " \
                     "a collection, images into the media library, Yoast SEO, and redirects from the old addresses."
      Cms::Plugins.submenu :wordpress_import, :tools, label: "Import from WordPress", path: -> { wordpress_import_runs_path },
        capability: "wordpress_import:run"
      Cms::Plugins.permissions :wordpress_import, "WordPress Import", %w[wordpress_import:run]
      Cms::Plugins.stylesheet :wordpress_import, "wordpress_import/wordpress_import"
    end
  end
end
