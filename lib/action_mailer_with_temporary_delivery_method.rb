# ok, let's all agree that package management is hard.
# the Rails load path looks like this:
# >> puts $:.join("\n")
# /home/www-data/bisento/releases/20090406132427/vendor/rails/activesupport/lib
# vendor/plugins/*
# /home/www-data/bisento/releases/20090406132427/vendor/rails/actionmailer/lib/action_mailer/vendor/text-format-0.6.3
# /home/www-data/bisento/releases/20090406132427/vendor/rails/actionmailer/lib/action_mailer/vendor/tmail-1.2.3
# /home/www-data/bisento/releases/20090406132427/vendor/rails/actionpack/lib/action_controller/vendor/html-scanner
# /home/www-data/bisento/releases/20090406132427/vendor/rails/activerecord/lib/../../activesupport/lib/active_support/vendor/memcache-client-1.5.0
# /home/www-data/bisento/releases/20090406132427/vendor/rails/activerecord/lib/../../activesupport/lib/active_support/vendor/xml-simple-1.0.11
# /home/www-data/bisento/releases/20090406132427/vendor/rails/activerecord/lib/../../activesupport/lib
# /home/www-data/bisento/releases/20090406132427/app/controllers/
# /home/www-data/bisento/releases/20090406132427/app
# /home/www-data/bisento/releases/20090406132427/app/models
# /home/www-data/bisento/releases/20090406132427/app/controllers
# /home/www-data/bisento/releases/20090406132427/app/helpers
# /home/www-data/bisento/releases/20090406132427/config
# /home/www-data/bisento/releases/20090406132427/lib
# vendor/plugins/validateable/lib
# vendor/plugins/catapult_error/lib
# /home/www-data/bisento/releases/20090406132427/vendor
# /home/www-data/bisento/releases/20090406132427/vendor/plugins/mocha/lib
# /home/www-data/bisento/releases/20090406132427/vendor/plugins/mocha/test
# /home/www-data/bisento/releases/20090406132427/vendor/plugins/mocha/examples
# app/apis
# /home/www-data/bisento/releases/20090406132427/vendor/rails/railties
# /home/www-data/bisento/releases/20090406132427/vendor/rails/railties/lib
# /home/www-data/bisento/releases/20090406132427/vendor/rails/activesupport/lib
# /home/www-data/bisento/releases/20090406132427/vendor/rails/actionpack/lib
# /home/www-data/bisento/releases/20090406132427/vendor/rails/activerecord/lib
# /home/www-data/bisento/releases/20090406132427/vendor/rails/actionmailer/lib
# /home/www-data/bisento/releases/20090406132427/vendor/rails/activeresource/lib
# /home/www-data/bisento/releases/20090406132427/config/../vendor/rails/railties/lib
# /usr/lib/ruby/gems/1.8/gems/builder-2.1.2/bin
# /usr/lib/ruby/gems/1.8/gems/builder-2.1.2/lib
# /usr/lib/ruby/gems/1.8/gems/tzinfo-0.3.9/bin
# /usr/lib/ruby/gems/1.8/gems/tzinfo-0.3.9/lib
# /usr/lib/ruby/gems/1.8/gems/rubyforge-1.0.0/bin
# /usr/lib/ruby/gems/1.8/gems/rubyforge-1.0.0/lib
# /usr/lib/ruby/gems/1.8/gems/rake-0.8.1/bin
# /usr/lib/ruby/gems/1.8/gems/rake-0.8.1/lib
# /usr/lib/ruby/gems/1.8/gems/hoe-1.5.3/bin
# /usr/lib/ruby/gems/1.8/gems/hoe-1.5.3/lib
# /usr/lib/ruby/gems/1.8/gems/ar_mailer-1.3.1/bin
# /usr/lib/ruby/gems/1.8/gems/ar_mailer-1.3.1/lib
# /usr/local/lib/site_ruby/1.8
# /usr/local/lib/site_ruby/1.8/x86_64-linux
# /usr/local/lib/site_ruby
# /usr/lib/ruby/1.8
# /usr/lib/ruby/1.8/x86_64-linux
# .
# which is generally fine (a lot of work goes into *making* it fine). The problem is with this line:
# /home/www-data/bisento/releases/20090406132427/vendor/rails/actionmailer/lib
# at this point in the load process, actionmailer is not loaded and '.' is a lower precedence than
# the gem. When it says require 'actionmailer' instead of loading actionmailer/lib/actionmailer.rb 
# it loads up the actionmailer gem. When we're trying to duck punch net/smtp and actionmailer, we are
# but in the wrong code. The solution is to move to the correct directory and require action_mailer.
# It hurts my feelings that an underscore and a directory change are required to load out of vendor
# instead of the gem, but that's what's what. @OM

require 'fileutils'
dir = FileUtils.pwd
FileUtils.cd File.join(File.dirname(__FILE__), %w(.. vendor rails actionmailer lib))
require 'action_mailer'

begin

  require "openssl"
  require "net/smtp"

  # :stopdoc:

  class Net::SMTP

    class << self
      send :remove_method, :start
    end

    def self.start( address, port = nil,
                    helo = 'localhost.localdomain',
                    user = nil, secret = nil, authtype = nil, use_tls = false,
                    &block) # :yield: smtp
      new(address, port).start(helo, user, secret, authtype, use_tls, &block)
    end

    alias tls_old_start start

    def start( helo = 'localhost.localdomain',
               user = nil, secret = nil, authtype = nil, use_tls = false ) # :yield: smtp
      start_method = use_tls ? :do_tls_start : :do_start
      if block_given?
        begin
          send start_method, helo, user, secret, authtype
          return yield(self)
        ensure
          do_finish
        end
      else
        send start_method, helo, user, secret, authtype
        return self
      end
    end

    private

    def do_tls_start(helodomain, user, secret, authtype)
      raise IOError, 'SMTP session already started' if @started
      check_auth_args user, secret, authtype if user or secret

      sock = timeout(@open_timeout) { TCPSocket.open(@address, @port) }
      @socket = Net::InternetMessageIO.new(sock)
      @socket.read_timeout = 60 #@read_timeout
      @socket.debug_output = STDERR #@debug_output

      check_response(critical { recv_response() })
      do_helo(helodomain)

      raise 'openssl library not installed' unless defined?(OpenSSL)
      starttls
      ssl = OpenSSL::SSL::SSLSocket.new(sock)
      ssl.sync_close = true
      ssl.connect
      @socket = Net::InternetMessageIO.new(ssl)
      @socket.read_timeout = 60 #@read_timeout
      @socket.debug_output = STDERR #@debug_output
      do_helo(helodomain)

      authenticate user, secret, authtype if user
      @started = true
    ensure
      unless @started
        # authentication failed, cancel connection.
          @socket.close if not @started and @socket and not @socket.closed?
        @socket = nil
      end
    end

    def do_helo(helodomain)
       begin
        if @esmtp
          ehlo helodomain
        else
          helo helodomain
        end
      rescue Net::ProtocolError
        if @esmtp
          @esmtp = false
          @error_occured = false
          retry
        end
        raise
      end
    end

    def starttls
      getok('STARTTLS')
    end

    alias tls_old_quit quit

    def quit
      begin
        getok('QUIT')
      rescue EOFError
      end
    end

  end unless Net::SMTP.private_method_defined? :do_tls_start or
             Net::SMTP.method_defined? :tls?

  module ActionMailerWithTemporaryDeliveryMethod
    def self.included(base)
      super
      base.class_eval do
        extend ClassMethods
      end
    end

    module ClassMethods
      def action_mailer_with_temporary_delivery_method(delivery_method = :smtp)
        existing_delivery_method = ActionMailer::Base.delivery_method
        existing_smtp_settings = ActionMailer::Base.smtp_settings
        begin
          ActionMailer::Base.delivery_method = delivery_method
          ActionMailer::Base.smtp_settings = {
            :address => "smtp.gmail.com",
            :port => "587",
            :domain => "yourdomain.com",
            :authentication => :plain,
            :user_name => "do-not-reply@yourdomain.com",
            :password => "yourpassword",
            :use_tls => true
          }
          yield
        ensure
          ActionMailer::Base.delivery_method = existing_delivery_method
          ActionMailer::Base.smtp_settings = existing_smtp_settings
        end
      end
    end

    def action_mailer_with_temporary_delivery_method(delivery_method = :smtp, &block)
      self.class.action_mailer_with_temporary_delivery_method(delivery_method, &block)
    end
  end
ensure
  FileUtils.cd dir
end