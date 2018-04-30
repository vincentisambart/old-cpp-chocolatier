require "pp"

class Converter
  def initialize(json)
    @json = json
    @declarations = {}
    @forward_declarations = {}
  end

  def find_decl(usr)
    decl = @declarations[usr] || @forward_declarations[usr]
    return decl if decl
    raise "Could not find declaration #{usr}"
  end

  def void_type?(type)
    type[:type_class] == "Builtin" && type[:name] == "Void"
  end

  def ptr_to_objc_id?(type)
    match?(type, {
      type_class: "ObjCObjectPointer",
      pointee: {
        type_class: "ObjCObject",
        base_type: {
          type_class: "Builtin",
          name: "ObjCId",
        },
      },
    })
  end

  def ptr_to_objc_sel?(type)
    match?(type, {
      type_class: "Pointer",
      pointee: {
        type_class: "Builtin",
        name: "ObjCSel",
      },
    })
  end

  def ptr_to_objc_class?(type)
    match?(type, {
      type_class: "ObjCObjectPointer",
      pointee: {
        type_class: "ObjCObject",
        base_type: {
          type_class: "Builtin",
          name: "ObjCClass",
        },
      },
    })
  end

  def match?(json, pattern)
    case pattern
    when Array
      return false unless json.is_a?(Hash)
      json.zip(pattern).all? {|j, p| match?(j, p) }
    when Hash
      return false unless json.is_a?(Hash)
      pattern.all? {|k, v| match?(json[k], v) }
    when String, Number
      json == pattern
    else
      raise "Unknown pattern type #{pattern.class}"
    end
  end

  def rustify_type(type)
    case type[:type_class]
    when "Builtin"
      case type[:name]
      when "Void"
        "libc::c_void"
      when "Char_U", "Char_S"
        "libc::c_char"
      when "UChar"
        "libc::c_uchar"
      when "UShort"
        "libc::c_ushort"
      when "UInt"
        "libc::c_uint"
      when "ULong"
        "libc::c_ulong"
      when "ULongLong"
        "libc::c_ulonglong"
      when "SChar"
        "libc::c_schar"
      when "Short"
        "libc::c_short"
      when "Int"
        "libc::c_int"
      when "Long"
        "libc::c_long"
      when "LongLong"
        "libc::c_longlong"
      when "Float"
        "libc::c_float"
      when "Double"
        "libc::c_double"
      when "Bool"
        "bool"
      else
        raise "Unknown builtin type #{type.inspect}"
      end
    when "Typedef"
      decl = find_decl(type[:decl_usr])
      if type[:name] == "BOOL" && decl[:type][:type_class] == "Builtin" && decl[:type][:name] = "SChar"
        "objc::runtime::BOOL"
      elsif type[:name] == "instancetype" && ptr_to_objc_id?(decl[:type])
        "Self"
      elsif type[:name] == "id" && ptr_to_objc_id?(decl[:type])
        "ObjCObjectPointer"
      elsif type[:name] == "SEL" && ptr_to_objc_sel?(decl[:type])
        "objc::runtime::Sel"
      elsif type[:name] == "Class" && ptr_to_objc_class?(decl[:type])
        "Class"
      else
        type[:name]
      end
    when "ObjCObjectPointer"
      if ptr_to_objc_id?(type)
        "ObjCObjectPointer"
      else
        pointee = type[:pointee]
        decl = find_decl(pointee[:interface_usr])
        decl[:name]
      end
    else
      "todo"
    end
  end

  def determine_module(decl)
    return "core" if decl[:is_implicit] && !decl[:location]
    file_path = decl[:location][:file]
    mod = case file_path
    when %r{/System/Library/Frameworks/([^./]+)\.framework/Headers/[^/.]+\.h\z}
      $1
    when %r{/System/Library/Frameworks/([^./]+)\.framework/Frameworks/[^/.]+.framework/Headers/[^/.]+\.h\z}
      $1
    when %r{/usr/include/([^/]+)/[^/.]+\.h\z}
      if $1 == "objc"
        "core"
      else
        $1
      end
    else
      raise "Couldn't find the module for #{file_path}"
    end
    mod.downcase
  end

  def rustify_method(decl)
    raise "Expected #{decl.inspect} to be a method declaration" unless decl[:kind] == "ObjCMethod"
    method_name = decl[:selector].gsub(":", "_")
    params = decl[:params].map {|param| "#{param[:name]}: #{rustify_type(param[:type])}" }
    params.unshift("&self") if decl[:is_instance_method]
    if void_type?(decl[:return_type])
      "fn #{method_name}(#{params.join(", ")})"
    else
      "fn #{method_name}(#{params.join(", ")}) -> #{rustify_type(decl[:return_type])}"
    end
  end

  def convert
    raise "Expecting a TranslationUnit declaration" unless @json[:kind] == "TranslationUnit"
    puts "extern crate objc;"
    puts "extern crate libc;"

    # A full declaration might come after its first use so make the list of all declarations first.
    @json[:children].each do |decl|
      if decl[:is_forward_declaration]
        @forward_declarations[decl[:usr]] = decl
      else
        @declarations[decl[:usr]] = decl
      end
    end

    @class_module = {}
    @protocol_module = {}
    @json[:children].each do |decl|
      next if decl[:is_forward_declaration]
      case decl[:kind]
      when "ObjCInterface"
        mod = determine_module(decl)
        @class_module[decl[:name]] = mod
      when "ObjCProtocol"
        mod = determine_module(decl)
        @protocol_module[decl[:name]] = mod
      end
    end

    @objc_declarations_per_module = {}
    @json[:children].each do |decl|
      next if decl[:is_forward_declaration]
      next unless %w{ObjCInterface ObjCProtocol ObjCCategory}.include?(decl[:kind])
      mod = determine_module(decl)
      methods = decl[:children].select {|child| child[:kind] == "ObjCMethod" }

      @objc_declarations_per_module[mod] ||= {}
      case decl[:kind]
      when "ObjCInterface"
        @objc_declarations_per_module[mod][:interface] ||= {}
        @objc_declarations_per_module[mod][:interface][decl[:name]] ||= {}
        target = @objc_declarations_per_module[mod][:interface][decl[:name]]
        if decl[:super_class_usr]
          super_class_decl = find_decl(decl[:super_class_usr])
          target[:super_class] = super_class_decl[:name]
        end
      when "ObjCProtocol"
        @objc_declarations_per_module[mod][:protocol] ||= {}
        @objc_declarations_per_module[mod][:protocol][decl[:name]] ||= {}
        target = @objc_declarations_per_module[mod][:protocol][decl[:name]]
      when "ObjCCategory"
        # If the category will end up in the same module, directly add methods to the class interface
        if mod == @class_module[decl[:class_name]]
          @objc_declarations_per_module[mod][:interface] ||= {}
          @objc_declarations_per_module[mod][:interface][decl[:class_name]] ||= {}
          target = @objc_declarations_per_module[mod][:interface][decl[:class_name]]
        else
          @objc_declarations_per_module[mod][:category] ||= {}
          @objc_declarations_per_module[mod][:category][decl[:class_name]] ||= {}
          target = @objc_declarations_per_module[mod][:category][decl[:class_name]]
        end
      end
      target[:methods] ||= []
      target[:methods].concat(methods)
      if decl[:protocols]
        target[:protocols] ||= []
        target[:protocols].concat(decl[:protocols])
      end
    end

    @objc_declarations_per_module.each do |mod, decls|
      puts "mod #{mod} {"

      (decls[:interface] || {}).each do |name, interface|
        base_traits = []
        if interface[:super_class]
          base_traits << "#{interface[:super_class]}Interface"
        end
        if interface[:protocols]
          base_traits.concat interface[:protocols].map {|protocol_name| "#{protocol_name}Protocol" }
        end

        puts "    pub struct #{name}(ObjCPointer);"

        if base_traits.empty?
          puts "    pub trait #{name}Interface {"
        else
          puts "    pub trait #{name}Interface: #{base_traits.join(", ")} {"
        end
        interface[:methods].each do |method_decl|
          puts "        #{rustify_method(method_decl)}"
        end
        puts "    }"

        puts <<-END
    impl ObjCObject for #{name} {
        fn ptr(&self) -> ObjCPointer {
            self.0
        }
        fn from_ptr_unchecked(ptr: ObjCPointer) -> NSObject {
            #{name}(ptr)
        }
    }
        END
        puts "    impl #{name}Interface for #{name} {}"
      end

      (decls[:protocol] || {}).each do |name, protocol|
        if protocol[:protocols]
          base_traits = protocol[:protocols].map {|protocol_name| "#{protocol_name}Protocol" }
          puts "    trait #{name}Protocol: #{base_traits.join(", ")} {"
        else
          puts "    trait #{name}Protocol {"
        end
        protocol[:methods].each do |method_decl|
          puts "        #{rustify_method(method_decl)}"
        end
        puts "    }"
      end

      (decls[:category] || {}).each do |class_name, category|
        if category[:protocols]
          base_traits = category[:protocols].map {|protocol_name| "#{protocol_name}Protocol" }
          puts "    trait #{class_name}Category: #{base_traits.join(", ")} {"
        else
          puts "    trait #{class_name}Category {"
        end
        category[:methods].each do |method_decl|
          puts "        #{rustify_method(method_decl)}"
        end
        puts "    }"
        puts "    impl #{class_name}Category for #{@class_module[class_name]}::#{class_name} {}"
      end

      puts "}"
    end
  end
end