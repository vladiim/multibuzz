# frozen_string_literal: true

module Logs
  class ArchiveService
    def initialize(log_dir: Rails.root.join("log"), s3_client: nil, bucket: nil, date: Date.yesterday)
      @log_dir = Pathname(log_dir)
      @s3_client = s3_client
      @bucket = bucket
      @date = date
    end

    def call
      return unless log_file.exist?

      upload_compressed_log
      log_file.delete
    end

    private

    attr_reader :log_dir, :date

    def upload_compressed_log
      s3_client.put_object(
        bucket: resolved_bucket,
        key: s3_key,
        body: compressed_content
      )
    end

    def compressed_content
      io = StringIO.new
      gz = Zlib::GzipWriter.new(io)
      gz.write(log_file.read)
      gz.close
      io.string
    end

    def s3_key
      "mbuzz/logs/#{date.strftime('%Y/%m/%d')}.log.gz"
    end

    def log_file
      @log_file ||= log_dir.join("production.log.#{date.iso8601}")
    end

    def s3_client
      @s3_client ||= Aws::S3::Client.new(
        region: credentials.fetch(:region),
        endpoint: credentials.fetch(:endpoint),
        access_key_id: credentials.fetch(:access_key_id),
        secret_access_key: credentials.fetch(:secret_access_key),
        force_path_style: true
      )
    end

    def resolved_bucket
      @bucket || credentials.fetch(:bucket)
    end

    def credentials
      @credentials ||= Rails.application.credentials.fetch(:do_spaces)
    end
  end
end
