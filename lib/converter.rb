require "pp"
require "set"

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

  def rustify_raw_type(type)
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
        "ObjCObjectPointer"
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
      "ObjCObjectPointer"
    when "ObjCTypeParam"
      "ObjCObjectPointer"
    when "Attributed"
      rustify_raw_type(type[:modified_type])
    when "Pointer", "Decayed"
      "*#{rustify_raw_type(type[:pointee])}"
    else
      p type
      "todo"
    end
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

  def rustify_method_raw(trait_name, decl)
    raise "Expected #{decl.inspect} to be a method declaration" unless decl[:kind] == "ObjCMethod"
    # im = instance method, cm = class method
    method_type = if decl[:is_instance_method] then "im" else "cm" end
    escaped_selector = decl[:selector].gsub(":", "_")

    code = ""
    code << "        pub unsafe fn #{trait_name}_#{method_type}_#{escaped_selector}("
    if decl[:is_instance_method]
      code << "ptr: ObjCObjectPointer"
    else
      code << "cls: &objc::runtime::Class"
    end
    unless decl[:params].empty?
      code << ", "
      code << decl[:params].map do |param|
        "#{param[:name]}: #{rustify_raw_type(param[:type])}"
      end.join(", ")
    end
    code << ") "
    unless void_type?(decl[:return_type])
      code << "-> #{rustify_raw_type(decl[:return_type])} "
    end
    code << "{\n"
    code << "            "
    if void_type?(decl[:return_type])
      # void methods must have their return type annotated
      code << "let _: () = "
    end
    if decl[:is_instance_method]
      code << "(*ptr)"
    else
      code << "cls"
    end
    code << ".send_message(*selectors::#{escaped_selector}, ("
    if decl[:params].length == 1
      code << decl[:params][0][:name]
      code << "," # tuples with one element must have a "," before the closing brace
    else
      code << decl[:params].map {|param| param[:name] }.join(", ")
    end
    code << ")).unwrap()"
    if void_type?(decl[:return_type])
      code << ";"
    end
    code << "\n"
    code << "        }\n"
    code
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
    @selectors_per_module = {}
    @json[:children].each do |decl|
      next if decl[:is_forward_declaration]
      next unless %w{ObjCInterface ObjCProtocol ObjCCategory}.include?(decl[:kind])
      mod = determine_module(decl)
      methods = decl[:children].select {|child| child[:kind] == "ObjCMethod" }

      @objc_declarations_per_module[mod] ||= {}
      @selectors_per_module[mod] ||= Set.new
      @selectors_per_module[mod].merge methods.map {|method| method[:selector] }

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

      puts <<-END
    #[allow(non_upper_case_globals)]
    mod selectors {
        use objc::runtime::Sel;

        lazy_static! {
      END
      @selectors_per_module[mod].to_a.sort.each do |selector|
        puts %{            pub static ref #{selector.gsub(":", "_")}: Sel = Sel::register("#{selector}");}
      end
      puts <<-END
        }
    }
      END

      if decls[:interface]
        puts <<-END
    #[allow(non_upper_case_globals)]
    mod classes {
        use objc::runtime::Class;

        lazy_static! {
    END
        decls[:interface].each do |name, interface|
          puts %{            pub static ref #{name}: &'static Class = Class::get("#{name}").unwrap();}
        end
        puts <<-END
        }
    }
          END
      end

      if mod == "core"
        puts <<-END
    pub type ObjCObjectPointer = *mut objc::runtime::Object;
    pub trait ObjCObject {
        fn ptr(&self) -> ObjCObjectPointer;
        fn from_ptr(ptr: ObjCObjectPointer) -> Self;
    }
        END
      end

      puts <<-END
    #[allow(non_snake_case)]
    mod raw {
        use objc;
        use objc::Message;
        use super::{selectors, ObjCObjectPointer};

      END

      (decls[:protocol] || {}).each do |name, protocol|
        protocol[:methods].each do |method|
          print rustify_method_raw("#{name}Protocol", method)
        end
      end

      (decls[:interface] || {}).each do |name, interface|
        interface[:methods].each do |method|
          print rustify_method_raw("#{name}Interface", method)
        end
      end

      (decls[:category] || {}).each do |class_name, protocol|
        protocol[:methods].each do |method|
          print rustify_method_raw("#{class_name}Category", method)
        end
      end

      puts "    }" # mod raw

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

      (decls[:interface] || {}).each do |name, interface|
        base_traits = []
        if interface[:super_class]
          base_traits << "#{interface[:super_class]}Interface"
        end
        if interface[:protocols]
          base_traits.concat interface[:protocols].map {|protocol_name| "#{protocol_name}Protocol" }
        end

        puts "    pub struct #{name}(ObjCObjectPointer);"

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
        fn ptr(&self) -> ObjCObjectPointer {
            self.0
        }
        fn from_ptr_unchecked(ptr: ObjCObjectPointer) -> NSObject {
            #{name}(ptr)
        }
    }
        END
        puts "    impl #{name}Interface for #{name} {}"
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