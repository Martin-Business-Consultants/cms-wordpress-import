# frozen_string_literal: true

# One import of a WordPress export: the file, what to bring, and how it went
# (counts of what was made, updated, reused and skipped, and a note for
# each thing that couldn't come over). The file is kept in the data
# directory until the import has run.
module WordpressImport
  class Run < ApplicationRecord
    self.table_name = "wordpress_import_runs"

    class Refused < StandardError; end

    STATUSES = %w[queued running succeeded failed].freeze
    MAX_FILE = 200.megabytes

    belongs_to :requested_by, class_name: "User", optional: true

    validates :status, inclusion: {in: STATUSES}

    scope :ordered, -> { order(created_at: :desc, id: :desc) }

    def self.start(file, by:, collection: "posts", media: true, redirects: true, drafts: true)
      raise Refused, "Choose the export file WordPress made (Tools › Export, an .xml file)." unless file.respond_to?(:read)
      raise Refused, "That file is over #{MAX_FILE / 1.megabyte}MB." if file.size > MAX_FILE

      run = create!(filename: file.original_filename.to_s, requested_by: by,
        options: {collection: collection.presence || "posts", media: media, redirects: redirects, drafts: drafts})
      run.path.dirname.mkpath
      IO.copy_stream(file, run.path)
      ImportJob.perform_later(run)
      run
    end

    def path = Cms.data_dir.join("wordpress_imports", "#{id}.xml")

    def import_now
      update!(status: "running")
      export = Export.new(path.read)
      importer = Importer.new(export, **options.symbolize_keys.slice(:collection, :media, :redirects, :drafts),
        logger: ->(line) { append(line) }).call
      update!(status: "succeeded", counts: importer.counts, finished_at: Time.current)
    rescue StandardError => error
      append(error.is_a?(Export::Invalid) ? error.message : "#{error.class.name.demodulize}: #{error.message}")
      update!(status: "failed", finished_at: Time.current)
    ensure
      FileUtils.rm_f(path) if finished?
    end

    def finished? = %w[succeeded failed].include?(status)
    def running? = %w[queued running].include?(status)

    def lines = log.to_s.lines.map(&:chomp)

    private

    def append(line) = update_columns(log: [log.presence, line].compact.join("\n"))
  end
end
