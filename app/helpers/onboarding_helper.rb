# frozen_string_literal: true

module OnboardingHelper
  SYNTAX_LANGUAGES = {
    "ruby" => "ruby",
    "python" => "python",
    "nodejs" => "javascript",
    "php" => "php",
    "shopify" => "javascript",
    "rest_api" => "bash"
  }.freeze

  def syntax_language_for(sdk)
    return "ruby" unless sdk

    SYNTAX_LANGUAGES.fetch(sdk.key, "ruby")
  end

  def pixel_code_for_onboarding
    api_key = @plaintext_api_key || test_api_key&.key_prefix || "YOUR_API_KEY"

    <<~JS
      // CONFIGURATION
      const API_KEY = "#{api_key}";
      const DEBUG = false;

      // DO NOT EDIT BELOW
      const API_URL = "https://mbuzz.co/api/v1";
      const VID_ATTR = "_mbuzz_visitor_id";
      const SID_ATTR = "_mbuzz_session_id";

      function log(msg, data) {
        if (DEBUG) console.log("[mbuzz] " + msg, data || "");
      }

      function cacheIds(vid, sid) {
        if (vid) {
          browser.sessionStorage.setItem("_mbuzz_cached_vid", vid);
          browser.sessionStorage.setItem("_mbuzz_cached_sid", sid || "");
        }
      }

      function getIds(checkout) {
        var attrs = (checkout && checkout.attributes) || [];
        var vid = null;
        var sid = null;
        for (var i = 0; i < attrs.length; i++) {
          if (attrs[i].key === VID_ATTR) vid = attrs[i].value;
          if (attrs[i].key === SID_ATTR) sid = attrs[i].value;
        }
        if (vid) { cacheIds(vid, sid); }
        return { vid: vid, sid: sid };
      }

      function trackEventWithIds(ids, eventType, props) {
        if (!ids.vid) { return; }
        var payload = {
          events: [{
            event_type: eventType,
            visitor_id: ids.vid,
            session_id: ids.sid,
            timestamp: new Date().toISOString(),
            properties: props || {}
          }]
        };
        fetch(API_URL + "/events", {
          method: "POST",
          headers: { "Authorization": "Bearer " + API_KEY, "Content-Type": "application/json" },
          body: JSON.stringify(payload)
        }).catch(function(e) { log("err", e.message); });
      }

      function getCachedIds(callback) {
        Promise.all([
          browser.sessionStorage.getItem("_mbuzz_cached_vid"),
          browser.sessionStorage.getItem("_mbuzz_cached_sid")
        ]).then(function(results) {
          callback({ vid: results[0], sid: results[1] });
        }).catch(function() {
          callback({ vid: null, sid: null });
        });
      }

      function identify(checkout, email, source) {
        var ids = getIds(checkout);
        if (ids.vid) {
          sendIdentify(email, ids.vid, source);
        } else {
          getCachedIds(function(cached) {
            sendIdentify(email, cached.vid, source);
          });
        }
      }

      function sendIdentify(email, vid, source) {
        var payload = {
          user_id: email,
          visitor_id: vid,
          traits: { email: email, source: source }
        };
        fetch(API_URL + "/identify", {
          method: "POST",
          headers: { "Authorization": "Bearer " + API_KEY, "Content-Type": "application/json" },
          body: JSON.stringify(payload)
        }).catch(function(e) { log("err", e.message); });
      }

      analytics.subscribe("checkout_started", function(evt) {
        var checkout = evt.data && evt.data.checkout;
        var ids = getIds(checkout);
        if (!ids.vid) { return; }
        var items = (checkout && checkout.lineItems) || [];
        if (items.length > 0) {
          var item = items[0];
          var variant = item.variant || {};
          var product = variant.product || {};
          var price = variant.price || {};
          trackEventWithIds(ids, "add_to_cart", {
            product_id: product.id,
            product_title: item.title,
            price: price.amount,
            quantity: item.quantity
          });
        }
        var total = checkout && checkout.totalPrice || {};
        trackEventWithIds(ids, "checkout", {
          total: total.amount,
          currency: checkout && checkout.currencyCode,
          item_count: items.length
        });
      });

      analytics.subscribe("checkout_contact_info_submitted", function(evt) {
        var checkout = evt.data && evt.data.checkout;
        var email = checkout && checkout.email;
        if (email) identify(checkout, email, "shopify_checkout");
      });

      analytics.subscribe("checkout_completed", function(evt) {
        var checkout = evt.data && evt.data.checkout;
        var email = checkout && checkout.email;
        if (email) identify(checkout, email, "shopify_checkout_completed");
      });
    JS
  end
end
