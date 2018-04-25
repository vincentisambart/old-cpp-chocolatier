require "pathname"

module JSONSerializer
  BASE_DIR = Pathname.new(__dir__).join("..").expand_path
  BINARY_PATH = BASE_DIR.join("bin", "json_serializer")
  SOURCE_PATH = BASE_DIR.join("src", "json_serializer.cpp")
end

require_relative "./json_serializer/builder.rb"
require_relative "./json_serializer/runner.rb"
