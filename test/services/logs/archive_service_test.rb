# frozen_string_literal: true

require "test_helper"
require "fileutils"

class Logs::ArchiveServiceTest < ActiveSupport::TestCase
  setup do
    @log_dir = Rails.root.join("tmp", "test_logs_#{SecureRandom.hex(8)}")
    FileUtils.mkdir_p(@log_dir)
  end

  teardown do
    FileUtils.rm_rf(@log_dir)
  end

  # --- Compression + Upload ---

  test "compresses yesterday's log and uploads to Spaces" do
    create_log_file(yesterday)

    s3_client = MockS3Client.new
    service(s3_client: s3_client).call

    assert_equal 1, s3_client.uploads.size

    upload = s3_client.uploads.first
    assert_equal expected_key(yesterday), upload[:key]
    assert upload[:body].bytesize > 0, "Should upload compressed content"
  end

  test "uses correct Spaces key format: logs/YYYY/MM/DD.log.gz" do
    create_log_file(yesterday)

    s3_client = MockS3Client.new
    service(s3_client: s3_client).call

    expected = "mbuzz/logs/#{yesterday.strftime('%Y/%m/%d')}.log.gz"
    assert_equal expected, s3_client.uploads.first[:key]
  end

  test "deletes local file after successful upload" do
    path = create_log_file(yesterday)

    service(s3_client: MockS3Client.new).call

    refute File.exist?(path), "Local log file should be deleted after upload"
  end

  test "uploads gzip-compressed content" do
    create_log_file(yesterday, content: "test log line\n")

    s3_client = MockS3Client.new
    service(s3_client: s3_client).call

    decompressed = Zlib::GzipReader.new(StringIO.new(s3_client.uploads.first[:body])).read
    assert_equal "test log line\n", decompressed
  end

  # --- Missing file ---

  test "completes without error when yesterday's log does not exist" do
    s3_client = MockS3Client.new

    assert_nothing_raised do
      service(s3_client: s3_client).call
    end

    assert_empty s3_client.uploads
  end

  # --- Upload failure ---

  test "preserves local file when upload fails" do
    path = create_log_file(yesterday)

    failing_client = MockS3Client.new(fail: true)

    assert_raises(RuntimeError) do
      service(s3_client: failing_client).call
    end

    assert File.exist?(path), "Local file should be preserved on upload failure"
  end

  private

  def yesterday
    @yesterday ||= Date.yesterday
  end

  def service(s3_client: MockS3Client.new)
    Logs::ArchiveService.new(log_dir: @log_dir, s3_client: s3_client, bucket: "test-bucket")
  end

  def create_log_file(date, content: "sample log output\n")
    path = @log_dir.join("production.log.#{date.iso8601}")
    File.write(path, content)
    path
  end

  def expected_key(date)
    "mbuzz/logs/#{date.strftime('%Y/%m/%d')}.log.gz"
  end

  class MockS3Client
    attr_reader :uploads

    def initialize(fail: false)
      @uploads = []
      @fail = fail
    end

    def put_object(params)
      raise RuntimeError, "S3 upload failed" if @fail

      @uploads << params
    end
  end
end
