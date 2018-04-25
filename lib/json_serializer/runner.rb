require_relative "../json_serializer"

require "shellwords"
require "json"

module AppleSDK
  def self.sdk_name(sdk)
    case sdk.to_sym
    when :mac_os, :macosx
      "macosx"
    when :ios, :iphoneos
      "iphoneos"
    when :ios_simulator, iphonesimulator
      "iphonesimulator"
    when :tv_os, :appletvos
      "appletvos"
    when :tv_os_simulator, :appletvsimulator
      "appletvsimulator"
    when :watch_os, :watchos
      "watchos"
    when :watch_os_simulator, :watchsimulator
      "watchsimulator"
    else
      raise "Unknown SDK type #{sdk}"
    end
  end

  def self.sdk_path(sdk)
    output = `xcrun --sdk #{sdk_name(sdk)} --show-sdk-path`
    raise "Could not find the path for the #{sdk} SDK" unless $?.success?
    output.strip
  end
end

module JSONSerializer
  module Runner
    def self.run_on_objc_file(file_path)
      sdk_path = AppleSDK.sdk_path(:mac_os)
      output = `#{BINARY_PATH.to_s.shellescape} #{file_path.to_s.shellescape} -- -x objective-c -isysroot #{sdk_path.to_s.shellescape}`
      raise "Error parsing #{file_path}: #{output}" unless $?.success?
      JSON.parse(output.strip)
    end
  end
end
