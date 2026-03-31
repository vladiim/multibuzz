# frozen_string_literal: true

module Score
  module ReportContent
    AD_SPEND_RANGES = {
      "<100k" => [ 50_000, 100_000 ],
      "100k-500k" => [ 100_000, 500_000 ],
      "500k-2m" => [ 500_000, 2_000_000 ],
      "2m-10m" => [ 2_000_000, 10_000_000 ],
      "10m+" => [ 10_000_000, 20_000_000 ],
      "na" => [ 100_000, 500_000 ]
    }.freeze

    # Estimated waste percentage by level [low, high]
    # Source: Dropbox/IEEE 2026 — platform attribution overstates 2-10x
    WASTE_BY_LEVEL = {
      1 => [ 0.20, 0.40 ],
      2 => [ 0.10, 0.20 ],
      3 => [ 0.05, 0.10 ],
      4 => [ 0.02, 0.05 ]
    }.freeze

    ROADMAPS = {
      1 => [
        { title: "Implement server-side tracking", why: "Client-side tracking loses 30-40% of data to ad blockers and ITP. Server-side captures what you're missing.", effort: "2-4 weeks with a developer, 1-2 days with an sGTM platform", tools: [ "mbuzz (from $29/mo)", "Stape ($20/mo)", "TAGGRS ($30/mo)", "Self-hosted sGTM (free)" ] },
        { title: "Deploy independent multi-touch attribution", why: "Replaces platform self-reported numbers with a neutral view. Deduplicates conversions that every channel claims.", effort: "1-2 weeks setup, ongoing", tools: [ "mbuzz (from $29/mo)", "Attribution App ($99/mo)", "Triple Whale (free tier)", "Ruler Analytics ($250/mo)" ] },
        { title: "Set up cross-channel deduplication", why: "When Google says 70 and Meta says 40 but you had 100 sales, deduplication reveals the truth.", effort: "Included with most MTA tools", tools: [ "Part of MTA setup above" ] },
        { title: "Connect CRM revenue to marketing touchpoints", why: "Ties actual closed revenue back to the marketing touches that influenced it. Moves from lead-counting to revenue attribution.", effort: "1-2 weeks depending on CRM complexity", tools: [ "Native CRM integrations in most MTA tools" ] },
        { title: "Compare at least 3 attribution models side by side", why: "No single model is 'right'. Comparing first-touch, last-touch, and linear reveals which channels look different under each lens.", effort: "Configuration, not development", tools: [ "Built into most MTA platforms" ] }
      ],
      2 => [
        { title: "Add a second measurement method (MMM or cohort analysis)", why: "MTA shows touchpoint-level detail but misses macro effects. A second method cross-validates your findings.", effort: "2-4 weeks for initial model, needs 12+ months of data", tools: [ "Robyn (free, Meta open-source)", "Meridian (free, Google open-source)", "Recast (from $35K/yr)", "Seeda (AU, from ~$1K/mo)" ] },
        { title: "Run your first geo-holdout experiment", why: "The only way to prove a channel actually works is to turn it off somewhere and measure the difference.", effort: "1 month runtime, 1 week setup", tools: [ "Google Conversion Lift (free, $5K min spend)", "GeoLift (free, open-source)", "Haus (enterprise)" ] },
        { title: "Build scenario-based budget models", why: "Move from 'last year + 10%' to 'what if we shift 20% from SEM to social?' Requires good data from steps 1-2.", effort: "Spreadsheet to start, 1-2 days", tools: [ "Excel/Sheets for MVP", "Robyn scenario planner (free)" ] },
        { title: "Track marginal CPA alongside average CPA", why: "Average CPA hides diminishing returns. The 1000th click costs more than the 100th. Marginal CPA shows where to stop spending.", effort: "Reporting change, not tooling", tools: [ "Any BI tool or MTA platform with spend data" ] }
      ],
      3 => [
        { title: "Establish a structured incrementality testing programme", why: "Ad-hoc experiments are valuable but one-off. A programme means continuous learning: test, learn, reallocate, re-test.", effort: "Ongoing \u2014 1 test per month minimum", tools: [ "Haus (from $132K/yr)", "Measured (enterprise)", "Google Conversion Lift (free)", "DIY geo-holdouts" ] },
        { title: "Calibrate MTA with causal experiment results", why: "Use incrementality results to adjust your MTA model weights. MTA shows the 'who', experiments prove the 'how much'.", effort: "Analysis after each experiment cycle", tools: [ "Custom analysis", "Rockerbox calibration feature" ] },
        { title: "Automate budget reallocation based on marginal returns", why: "Manual reallocation is slow. Automated rules shift budget to proven winners weekly, not quarterly.", effort: "Rules engine setup, 2-4 weeks", tools: [ "Custom scripts", "Platform budget rules", "Paramark (advisory + platform)" ] }
      ],
      4 => [
        { title: "You're at the top", why: "Very few companies reach Level 4. Focus on maintaining your testing cadence, expanding to new channels, and sharing your methodology.", effort: "Ongoing", tools: [ "Your existing stack" ] }
      ]
    }.freeze

    DIMENSION_INSIGHTS = {
      "reporting" => {
        1 => "You're relying on individual channel dashboards for reporting. Each platform shows its own version of reality, making it impossible to get a unified view of marketing performance.",
        2 => "You have a unified analytics view pulling data from multiple sources. You can answer 'what happened?' confidently, but response time to underperformance is still slow.",
        3 => "Your reporting is automated with alerts and regular optimisation cycles. You can identify and respond to underperformance weekly, freeing analysts for higher-value work.",
        4 => "Real-time or near-real-time reporting with automated reallocation triggers. Measurement drives decisions continuously, not just in review meetings."
      },
      "attribution" => {
        1 => "You're using last-click or platform-reported attribution. Every channel grades its own homework \u2014 combined, they claim 2-3x your actual conversions.",
        2 => "You compare multiple attribution models and can see how credit shifts between them. You've moved past single-model thinking but haven't yet validated with causal methods.",
        3 => "Your attribution is cross-validated with a second methodology. When MTA and MMM disagree, you investigate rather than panic.",
        4 => "Your multi-touch attribution is calibrated by incrementality testing. You know both who touched the customer and whether that touch actually caused the conversion."
      },
      "experimentation" => {
        1 => "You haven't run channel-level holdout experiments. Budget decisions are based on correlation, not proven causation.",
        2 => "You've discussed or attempted informal experiments. The willingness is there but a structured programme isn't.",
        3 => "You run geo-holdout or similar experiments periodically. You're building causal evidence, but it's not yet a continuous programme.",
        4 => "Continuous experimentation programme with regular holdouts. You can prove what's working and feed those results back into your models automatically."
      },
      "forecasting" => {
        1 => "Budget setting is based on last year's numbers or platform-reported targets. Forecasting is essentially backward-looking guesswork.",
        2 => "You're using platform-reported ROAS or CPA targets to set budgets. Better than gut feel, but still based on inflated numbers.",
        3 => "You build scenario-based models \u2014 'what if we shift budget from SEM to social?' You're modelling outcomes before committing spend.",
        4 => "Budget optimisation based on proven incrementality. Money flows to channels with demonstrated marginal returns, automatically and continuously."
      },
      "channels" => {
        1 => "Only 1-2 channels are measured. You're flying blind on everything outside paid search and paid social.",
        2 => "You measure paid channels plus organic and email. A broader view, but offline and brand channels are still invisible.",
        3 => "All digital channels plus some offline are in your measurement model. You're approaching a complete picture.",
        4 => "Full omnichannel measurement including TV, events, direct mail, and brand campaigns. Nothing material is unmeasured."
      },
      "infrastructure" => {
        1 => "Client-side JavaScript tags (GA4, platform pixels) are your primary data collection. You're losing 30-40% of data to ad blockers and browser privacy features.",
        2 => "You've added some server-side forwarding alongside client-side tracking. Data quality is improving but the foundation is still fragile.",
        3 => "Server-side tracking is primary with first-party data strategy. Your measurement works without third-party cookies and is resilient to browser changes.",
        4 => "Full server-side infrastructure with first-party data unified in a warehouse. Privacy-resilient, future-proof, and the foundation for advanced modelling."
      }
    }.freeze
  end
end
