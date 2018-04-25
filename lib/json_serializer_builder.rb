require "pathname"
require "shellwords"
require "fileutils"

class JSONSerializerBuilder
  @base_dir = Pathname.new(__dir__).join("..").expand_path
  @json_serializer_binary_path = @base_dir.join("bin", "json_serializer")
  @json_serializer_source_path = @base_dir.join("src", "json_serializer.cpp")
  def self.serializer_available?
    @json_serializer_binary_path.exist? &&
      @base_dir.join("lib", "clang", llvm_version_used_by_executable, "include").directory?
  end

  def self.llvm_version_used_by_executable
    return nil unless @json_serializer_binary_path.exist?
    output = `#{@json_serializer_binary_path.to_s.shellescape} -version`.strip
    raise "Error running #{json_serializer_binary_path}" unless $?.success?
    match_data = /LLVM version ([0-9.]+)/.match(output)
    raise "Could not find LLVM version used to build #{@json_serializer_binary_path}" unless match_data
    match_data[1]
  end

  def self.config_command(path, *args)
    command = "#{path.to_s.shellescape} #{args.map {|arg| arg.to_s.shellescape }.join(" ")}"
    output = `#{command}`
    raise "Error running #{command}: #{output}" unless $?.success?
    output.strip
  end

  def self.find_llvm_config
    if env_var = ENV["LLVM_CONFIG"]
      raise "Incorrect llvm-config path specified: #{env_var}" unless File.executable?(env_var)
      return env_var
    end
    # Look if llvm-config is in the PATH
    in_path = `which llvm-config`.strip
    return in_path unless in_path.empty?
    # If Homebrew is not installed, no fallback
    return nil if `which brew`.strip.empty?
    # Then try in the Homebrew default install directory
    brew_llvm_prefix = `brew --prefix llvm`.strip
    homebrew_default_llvm_config = File.join(brew_llvm_prefix, 'bin', 'llvm-config')
    return homebrew_default_llvm_config if File.exist?(homebrew_default_llvm_config)
    # llvm might not be activated, or if the user installed an older version of llvm
    # it might be for example in the llvm@5 directory, so search directly in the cellar
    brew_cellar = `brew --cellar`.strip
    Dir.glob(File.join(brew_cellar, "llvm*", "*", "bin", "llvm-config"))
      .sort_by {|path| Gem::Version.new(config_command(path, "--version")) }
      .last
  end

  def self.llvm_config_path
    llvm_config = find_llvm_config
    if llvm_config
      Pathname.new(llvm_config)
    else
      nil
    end
  end

  def self.up_to_date?
    return false unless serializer_available?
    @json_serializer_source_path.mtime <= @json_serializer_binary_path.mtime
  end

  def self.build
    puts "Rebuilding the JSON serializer..."
    llvm_config_path = self.llvm_config_path
    raise "Could not find llvm-config. To install LLVM+clang with Hoembrew: brew install llvm" unless llvm_config_path
    llvm_version = config_command(llvm_config_path, "--version")
    llvm_prefix = Pathname.new(config_command(llvm_config_path, "--prefix"))

    # libTooling expects the clang headers to be at a specific relative directory
    # http://clang.llvm.org/docs/LibTooling.html#builtin-includes
    copy_destination = @base_dir.join("lib", "clang", llvm_version)
    FileUtils.mkdir_p(copy_destination)
    FileUtils.cp_r(
      llvm_prefix.join("lib", "clang", llvm_version, "include"),
      copy_destination,
      # The file are copied without write rights so to overwrite the file must be removed
      remove_destination: true,
    )

    cxxflags = config_command(llvm_config_path, "--cxxflags")
    include_dir = @base_dir.join("include")
    ldflags = config_command(llvm_config_path, "--ldflags")
    libs = config_command(llvm_config_path, "--libs")
    system_libs = config_command(llvm_config_path, "--system-libs")
    clang_libs = "-lclangFrontend -lclangSerialization -lclangDriver -lclangTooling -lclangParse -lclangSema -lclangAnalysis -lclangEdit -lclangAST -lclangLex -lclangBasic -lclangIndex"
    command = "clang++ -o #{@json_serializer_binary_path.to_s.shellescape} -g -O2 #{cxxflags} -I#{include_dir.to_s.shellescape} #{ldflags} #{libs} #{system_libs} #{clang_libs} -stdlib=libc++ -std=c++14 #{@json_serializer_source_path.to_s.shellescape}"
    raise "Error executing #{command}" unless system command
  end
end
