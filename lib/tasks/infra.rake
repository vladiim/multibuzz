# frozen_string_literal: true

namespace :infra do
  desc "Run infrastructure health checks against scaling thresholds"
  task health: :environment do
    results = Infrastructure::HealthCheckService.new.call

    results.each do |check|
      label = check[:status].to_s.upcase.ljust(8)
      puts "[#{label}] #{check[:name]}: #{check[:display]}"
    end

    failures = results.select { |c| c[:status] == :critical }
    if failures.any?
      abort "\nCRITICAL: #{failures.map { |f| f[:name] }.join(', ')}"
    end

    warnings = results.select { |c| c[:status] == :warning }
    if warnings.any?
      warn "\nWARNING: #{warnings.map { |w| w[:name] }.join(', ')}"
    end
  end
end
