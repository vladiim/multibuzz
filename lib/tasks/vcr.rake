# frozen_string_literal: true

namespace :vcr do
  desc "Scan committed VCR cassettes for unfiltered secrets. Exits non-zero on any match."
  task :check_cassettes do
    cassette_glob = "test/vcr_cassettes/**/*.yml"

    leak_patterns = {
      "Bearer access token in Authorization header"      => /Authorization:\s*-?\s*Bearer\s+EAA[A-Za-z0-9_-]{20,}/i,
      "Meta access token in URL or body (EAA prefix)"    => /\bEAA[A-Za-z0-9_-]{50,}/,
      "Unfiltered access_token query param"              => /access_token=(?!<META_ACCESS_TOKEN>)[A-Za-z0-9_-]{20,}/,
      "Unfiltered appsecret_proof"                       => /appsecret_proof=(?!<APPSECRET_PROOF>)[A-Fa-f0-9]{30,}/,
      "Unfiltered fb_exchange_token"                     => /fb_exchange_token=(?!<FB_EXCHANGE_TOKEN>)[A-Za-z0-9_-]{20,}/,
      "Unfiltered client_secret"                         => /client_secret=(?!<META_APP_SECRET>)[A-Za-z0-9_-]{20,}/,
      "Unfiltered OAuth code"                            => /[?&]code=(?!<OAUTH_CODE>)[A-Za-z0-9_-]{20,}/,
      "Unredacted real ad account ID (act_NNN…)"         => /act_(?!TEST_)[0-9]{6,}/
    }.freeze

    leaks = []
    Dir.glob(cassette_glob).each do |path|
      content = File.read(path)
      leak_patterns.each do |label, pattern|
        next unless content.match?(pattern)

        leaks << "  #{path} — #{label}"
      end
    end

    if leaks.empty?
      puts "OK — #{Dir.glob(cassette_glob).size} cassette(s) scanned, no leak patterns matched."
    else
      puts "FAIL — leak patterns matched in committed cassettes:"
      puts leaks.join("\n")
      abort "Refusing to proceed. Re-record with stronger filters or scrub the cassette manually."
    end
  end
end
