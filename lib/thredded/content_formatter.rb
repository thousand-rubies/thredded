# frozen_string_literal: true

module Thredded
  # Generates HTML from content source.
  class ContentFormatter
    class << self
      # Sanitization allowlist options.
      attr_accessor :allowlist

      # TODO: v2.0: drop alias and just use allowlist
      alias_attribute :whitelist, :allowlist

      # Filters that run before processing the markup.
      # input: markup, output: markup.
      attr_accessor :before_markup_filters

      # Markup filters, such as BBCode, Markdown, Autolink, etc.
      # input: markup, output: html.
      attr_accessor :markup_filters

      # Filters that run after processing the markup.
      # input: html, output: html.
      attr_accessor :after_markup_filters

      # Filters that sanitize the resulting HTML.
      # input: html, output: sanitized html.
      attr_accessor :sanitization_filters

      # Filters that run after sanitization
      # input: sanitized html, output: html
      attr_accessor :after_sanitization_filters

      # TODO: v1.1: only allow html-pipeline >= 2.14.1 and drop this
      def sanitization_filter_uses_allowlist?
        defined?(HTML::Pipeline::SanitizationFilter::ALLOWLIST)
      end

      def sanitization_filter_allowlist_config
        if sanitization_filter_uses_allowlist?
          HTML::Pipeline::SanitizationFilter::ALLOWLIST
        else
          HTML::Pipeline::SanitizationFilter::WHITELIST
        end
      end
    end

    self.allowlist = sanitization_filter_allowlist_config.deep_merge(
      elements: sanitization_filter_allowlist_config[:elements] + %w[abbr iframe span figure figcaption],
      transformers: sanitization_filter_allowlist_config[:transformers] + [
        ->(env) {
          next unless env[:node_name] == 'a'
          a_tag = env[:node]
          a_tag['href'] ||= '#'
          if %r{^(?:[a-z]+:)?//}.match?(a_tag['href'])
            a_tag['target'] = '_blank'
            a_tag['rel']    = 'nofollow noopener'
          end
        }
      ],
      attributes: {
        'a'      => %w[href rel],
        'abbr'   => %w[title],
        'span'   => %w[class],
        'div'    => %w[class],
        'img'    => %w[src longdesc class],
        'th'     => %w[style],
        'td'     => %w[style],
        :all     => sanitization_filter_allowlist_config[:attributes][:all] +
          %w[aria-expanded aria-label aria-labelledby aria-live aria-hidden aria-pressed role],
      },
      css: {
        properties: %w[text-align],
      }
    )

    self.before_markup_filters = [
      Thredded::HtmlPipeline::SpoilerTagFilter::BeforeMarkup
    ]

    self.markup_filters = [
      Thredded::HtmlPipeline::KramdownFilter,
    ]

    self.after_markup_filters = [
      # AutolinkFilter is required because Kramdown does not autolink by default.
      # https://github.com/gettalong/kramdown/issues/306
      Thredded::HtmlPipeline::AutolinkFilter,
      Thredded::HtmlPipeline::AtMentionFilter,
      Thredded::HtmlPipeline::SpoilerTagFilter::AfterMarkup,
    ]

    self.sanitization_filters = [
      HTML::Pipeline::SanitizationFilter,
    ]

    self.after_sanitization_filters = [
      Thredded::HtmlPipeline::OneboxFilter,
      Thredded::HtmlPipeline::WrapIframesFilter,
    ]

    # All the HTML::Pipeline filters, read-only.
    def self.pipeline_filters
      filters = [
        *before_markup_filters,
        *markup_filters,
        *after_markup_filters,
        *sanitization_filters,
        *after_sanitization_filters
      ]
      # Changing the result in-place has no effect on the ContentFormatter output,
      # and is most likely the result of a programmer error.
      # Freeze the array so that in-place changes raise an error.
      filters.freeze
    end

    # @param view_context [Object] the context of the rendering view.
    # @param pipeline_options [Hash]
    def initialize(view_context, pipeline_options = {})
      @view_context = view_context
      @pipeline_options = pipeline_options
    end

    # @param content [String]
    # @return [String] formatted and sanitized html-safe content.
    def format_content(content)
      pipeline = HTML::Pipeline.new(content_pipeline_filters, content_pipeline_options.deep_merge(@pipeline_options))
      result = pipeline.call(content, view_context: @view_context)
      # rubocop:disable Rails/OutputSafety
      result[:output].to_s.html_safe
      # rubocop:enable Rails/OutputSafety
    end

    # @param content [String]
    # @return [String] a quote containing the formatted content
    def self.quote_content(content)
      result = String.new(content)
      result.gsub!(/^(?!$)/, '> ')
      result.gsub!(/^$/, '>')
      result << "\n" unless result.end_with?("\n")
      result << "\n"
      result
    end

    protected

    # @return [Array<HTML::Pipeline::Filter]>]
    def content_pipeline_filters
      ContentFormatter.pipeline_filters
    end

    # @return [Hash] options for HTML::Pipeline.new
    def content_pipeline_options
      option = if self.class.sanitization_filter_uses_allowlist?
                 :allowlist
               else
                 # TODO: v1.1: only allow html-pipeline >= 2.14.1 and drop this
                 :whitelist
               end
      {
        asset_root: Rails.application.config.action_controller.asset_host || '',
        option => ContentFormatter.allowlist
      }
    end
  end
end
