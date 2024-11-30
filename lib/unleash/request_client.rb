require 'unleash/configuration'
require 'unleash/toggle_fetcher'
require 'unleash/metrics_reporter'
require 'unleash/scheduled_executor'
require 'unleash/variant'
require 'unleash/util/http'
require 'logger'
require 'time'

module Unleash
  class RequestClient

    def initialize(disable_metrics: false, context: nil, **context_options)
      @disable_metrics = disable_metrics
      @context = context || Context.new(context_options)
    end

    def context
      @context
    end

    def is_metrics_enabled?
      @disable_metrics || Unleash.configuration.disable_metrics
    end

    def disable_metrics!
      @disable_metrics = true
    end

    def enable_metrics!
      if Unleash.configuration.disable_metrics
        Unleash.logger.warn "Unleash::Client is configured to not use metrics! Calling enable_metrics! will have no effect."
      end
      @disable_metrics = true
    end

    # metrics_enabled? is a more ruby idiomatic method name than is_metrics_enabled?
    alias metrics_enabled? is_metrics_enabled?

    def is_enabled?(feature, default_value_param = false, &fallback_blk)
      Unleash.logger.debug "Unleash::Client.is_enabled? feature: #{feature} with context #{context}"

      default_value = if block_given?
                        default_value_param || !!fallback_blk.call(feature, context)
                      else
                        default_value_param
                      end

      toggle_enabled = Unleash.engine.enabled?(feature, context)
      if toggle_enabled.nil?
        Unleash.logger.debug "Unleash::Client.is_enabled? feature: #{feature} not found"
        count_toggle(feature, false)
        return default_value
      end

      count_toggle(feature, toggle_enabled)

      toggle_enabled
    end

    def is_disabled?(feature, default_value_param = true, &fallback_blk)
      !is_enabled?(feature, !default_value_param, &fallback_blk)
    end

    # enabled? is a more ruby idiomatic method name than is_enabled?
    alias enabled? is_enabled?
    # disabled? is a more ruby idiomatic method name than is_disabled?
    alias disabled? is_disabled?

    # execute a code block (passed as a parameter), if is_enabled? is true.
    def if_enabled(feature, default_value = false, &blk)
      yield(blk) if is_enabled?(feature, context, default_value)
    end

    # execute a code block (passed as a parameter), if is_disabled? is true.
    def if_disabled(feature, default_value = true, &blk)
      yield(blk) if is_disabled?(feature, context, default_value)
    end

    def get_variant(feature, fallback_variant = disabled_variant)
      variant = Unleash.engine.get_variant(feature, context)

      if variant.nil?
        Unleash.logger.debug "Unleash::Client.get_variant variants for feature: #{feature} not found"
        count_toggle(feature, false)
        return fallback_variant
      end

      variant = Variant.new(variant)

      count_variant(feature, variant.name)
      count_toggle(feature, variant.feature_enabled)

      # TODO: Add to README: name, payload, enabled (bool)

      variant
    end

    private

    def count_toggle(feature, enabled)
      return unless metrics_enabled?
      Unleash.engine.count_toggle(feature, enabled)
    end

    def count_variant(feature, enabled)
      return unless metrics_enabled?
      Unleash.engine.count_variant(feature, enabled)
    end

    def disabled_variant
      @disabled_variant ||= Unleash::Variant.disabled_variant
    end
  end
end
