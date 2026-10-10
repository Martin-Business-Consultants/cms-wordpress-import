# WordPress Import

A plugin for [Libre Publish](https://github.com/Martin-Business-Consultants/libre-publish)
that brings a WordPress site over from its export file.

Tools › Import from WordPress takes the `.xml` file WordPress makes (Tools ›
Export › All content) and brings over:

- **Pages**, under their parents, each page's content as a Text block.
- **Posts**, as entries of a collection (`posts` unless you pick another). A
  collection that doesn't exist is made with an excerpt, a featured image,
  categories and tags; one that does is given the fields it lacks.
- **Images and files**, downloaded into the media library's `/wordpress`
  folder. Every size WordPress made of an image (`photo-300x200.jpg`) points
  at the one asset.
- **SEO** from Yoast: the title, the description and noindex. The featured
  image becomes the sharing image.
- **Redirects** from every old address that changes (`/2025/04/raised-beds/`)
  to the new one, so links and search results keep working. Links between
  pages and posts in the content point at the new addresses too.

Drafts, pending and private pages and posts come in as drafts, unless you
leave them out. Running it again updates what it brought before, found by
slug, and reuses the images it already downloaded. Comments, menus, widgets
and custom post types stay behind.

The content keeps WordPress's HTML, without the block editor's comments.
The website sanitizes it when it draws the page.

## Install

Needs Libre Publish 1.12 or newer. In Settings › Plugins, under "Add a
plugin", enter `Martin-Business-Consultants/cms-wordpress-import` and press
Install, then switch it on. It's in the Tools menu. Only admins can run it,
unless a role is given `wordpress_import:run`.

## Development

Its specs run inside the CMS, with the plugin in `plugins/`:

    ln -s ../../cms-wordpress-import plugins/wordpress_import
    bin/rspec plugins/wordpress_import/spec

Licensed under the Functional Source License (FSL-1.1-MIT, `LICENSE.md`).
