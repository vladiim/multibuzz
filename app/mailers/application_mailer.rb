class ApplicationMailer < ActionMailer::Base
  default from: "mbuzz <hello@mbuzz.co>"
  layout "mailer"
end
