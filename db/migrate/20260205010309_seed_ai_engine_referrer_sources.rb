class SeedAiEngineReferrerSources < ActiveRecord::Migration[8.0]
  AI_ENGINES = [
    { domain: "chatgpt.com", source_name: "ChatGPT" },
    { domain: "chat.openai.com", source_name: "ChatGPT" },
    { domain: "perplexity.ai", source_name: "Perplexity" },
    { domain: "claude.ai", source_name: "Claude" },
    { domain: "gemini.google.com", source_name: "Gemini" },
    { domain: "copilot.microsoft.com", source_name: "Copilot" },
    { domain: "meta.ai", source_name: "Meta AI" },
    { domain: "grok.x.ai", source_name: "Grok" },
    { domain: "you.com", source_name: "You.com" },
    { domain: "phind.com", source_name: "Phind" },
    { domain: "kagi.com", source_name: "Kagi" }
  ].freeze

  def up
    now = Time.current
    records = AI_ENGINES.map do |engine|
      engine.merge(
        medium: "ai",
        data_origin: "custom",
        is_spam: false,
        created_at: now,
        updated_at: now
      )
    end

    ReferrerSource.upsert_all(records, unique_by: :domain, update_only: [:source_name, :medium, :data_origin])
  end

  def down
    ReferrerSource.where(domain: AI_ENGINES.map { |e| e[:domain] }).delete_all
  end
end
