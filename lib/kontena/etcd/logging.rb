require 'logger'

# per-class logger, using the class name as the progname
#
# Use LOG_LEVEL=debug to configure
module Kontena::Etcd::Logging
  @log_level = ENV.fetch('LOG_LEVEL', Logger::INFO)

  def self.log_level
    @log_level
  end
  # @param level [Integer, String] 0.. or one of 'debug', 'info', ...
  def log_level=(level)
    @log_level = level
  end

  module ClassMethods
    def log_level=(level)
      @log_level = level
    end

    # Normalize configured logging to level for Logger#level=
    #
    # @return [Integer, String]
    def log_level
      level = @log_level || Kontena::Etcd::Logging.log_level
      level = level.to_i if level =~ /\d+/
      level
    end

    def logger(progname, output: $stderr, level: nil)
      logger = Logger.new(output)
      logger.level = level || log_level
      logger.progname = progname

      return logger
    end
  end

  def self.included(base)
    base.extend ClassMethods
  end

  # @return [Logger]
  def logger(progname = nil, **opts)
    if progname
      self.class.logger progname, **opts
    else
      @logger ||= self.class.logger self.class.name
    end
  end
end
