require 'paperclip-qiniu/exceptions'

module Paperclip
  module Storage
    module Qiniu
      def self.extended base
        begin
          require 'qiniu-rs'
        rescue LoadError => e
          e.message << " (You may need to install the qiniu-rs gem)"
          raise e
        end unless defined?(::Qiniu)

        base.instance_eval do
          # unless @options[:url].to_s.match(/^:qiniu.*url$/)
          #   @options[:path]  = @options[:path].gsub(/:url/, @options[:url]).gsub(/\A:rails_root\/public\/system\//, '')
          #   @options[:url]   = ':qiniu_public_url'
          # end
          Paperclip.interpolates(:qiniu_public_url) do |attachment, style|
            attachment.public_url(style)
          end unless Paperclip::Interpolations.respond_to? :qiniu_public_url
        end

      end

      def exists?(style = default_style)
        init
        !!::Qiniu::RS.stat(bucket, path(style))
      end

      def flush_writes
        init
        for style, file in @queued_for_write do
          log("saving #{path(style)}")
          retried = false
          begin
            upload(file, path(style))
          ensure
            file.rewind
          end
        end

        after_flush_writes # allows attachment to clean up temp files

        @queued_for_write = {}
      end

      def flush_deletes
        init
        for path in @queued_for_delete do
          ::Qiniu::RS.delete(bucket, path)
        end
        @queued_for_delete = []
      end

      def public_url(style = nil)
        style = style.to_s if style.is_a?(Symbol)
        style = "-#{style}" if style
        
        init
        
        if @options[:qiniu_host]
          the_url = "#{@options[:qiniu_host]}/#{path(:original)}#{style}"
          unless style
            download_token = ::Qiniu::RS.generate_download_token pattern: the_url.gsub('http://', '')
            the_url << "?token=#{download_token}"
          end
          the_url
        else
          res = ::Qiniu::RS.get(bucket, path(:original))
          if res
            "#{res["url"]}#{style}"
          else
            nil
          end
        end
      end
      
      def url(style = nil)
        public_url(style)
      end

      private

      def init
        return if @inited
        ::Qiniu::RS.establish_connection! @options[:qiniu_credentials]
        inited = true
      end

      def upload(file, qiniu_key)
        log("upload file: #{qiniu_key}")
        upload_token = ::Qiniu::RS.generate_upload_token :scope => bucket
        opts = {:uptoken            => upload_token,
                 :file               => file.path,
                 :key                => qiniu_key,
                 :bucket             => bucket,
                 :mime_type          => file.content_type,
                 :enable_crc32_check => true}
        unless ::Qiniu::RS.upload_file(opts)
          raise Paperclip::Qiniu::UploadFailed
        end
      end

      def bucket
        @options[:bucket] || raise("bucket is nil")
      end

    end
  end
end
