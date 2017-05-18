require 'singleton'

class ConfigReader

  CONFIG_FILE_PATH = "./config.rb"

  include Singleton

  def initialize
    @writeable = true
    instance_eval File.read(CONFIG_FILE_PATH), CONFIG_FILE_PATH
    @writeable = false
  end

  def method_missing(m, *args, &block)
    self.instance_variable_set "@#{m}", args[0] if args.size == 1 && @writeable
  end

  def self.method_missing(m, *args, &block)
    instance.instance_variable_get "@#{m}" if args.size == 0
  end

end
