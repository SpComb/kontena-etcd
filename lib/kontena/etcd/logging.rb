require 'logger'

module Kontena::Etcd
  module Logging
    def logger!
      logger = Logger.new(STDERR)
      logger.level = Logger::DEBUG
      logger.progname = self.class.name

      return logger
    end

    # @return [Logger]
    def logger
      @logger ||= self.logger!
    end
  end
end
