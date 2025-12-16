# frozen_string_literal: true

require_relative "app"

# Mbuzz tracking middleware - handles cookies and session creation
use Mbuzz::Middleware::Tracking

run MbuzzRubyTestapp
