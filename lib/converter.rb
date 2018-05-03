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
        "bool"
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
    when "ObjCTypeParam"
      type[:name]
    else
      p type
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
      raise "Couldn't determine the module for #{file_path}"
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
        "objc::runtime::BOOL" # TODO: Should use our own typedef (should not need special treatment here (even though special treatment will be needed for conversion to and from bool)
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

  def rustify_raw_method(decl)
    raise "Expected #{decl.inspect} to be a method declaration" unless decl[:kind] == "ObjCMethod"
    # im = instance method, cm = class method
    method_type = if decl[:is_instance_method] then "im" else "cm" end
    escaped_selector = decl[:selector].gsub(":", "_")

    code = ""
    code << "        pub unsafe fn #{escaped_selector}("
    if decl[:is_instance_method]
      code << "&self"
    end
    unless decl[:params].empty?
      code << ", " if decl[:is_instance_method]
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
      code << "(*self.ptr())"
    else
      code << "Self::class()"
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

  def type_handled?(type)
    case type[:type_class]
    when "Builtin"
      true
    when "Typedef"
      decl = find_decl(type[:decl_usr])
      type_handled?(decl[:type])
    when "ObjCObjectPointer",
      true
    when "ObjCTypeParam"
      false
    when "Attributed"
      type_handled?(type[:modified_type])
    when "Pointer", "Decayed"
      type_handled?(type[:pointee])
    else
      false
    end
  end

  def method_handled?(decl)
    raise "Expected #{decl.inspect} to be a method declaration" unless decl[:kind] == "ObjCMethod"
    type_handled?(decl[:return_type]) && decl[:params].all? {|param| type_handled?(param[:type]) }
  end

  class CDefinitionsSet
    attr_reader :types, :structs, :enums

    def initialize(converter)
      @converter = converter
      @types = Set.new
      @structs = Set.new
      @enums = Set.new
      @unions = Set.new
    end

    def to_h
      h = {}
      h[:types] = @types unless @types.empty?
      h[:structs] = @structs unless @structs.empty?
      h[:enums] = @enums unless @enums.empty?
      h[:unions] = @unions unless @unions.empty?
      h
    end

    def include?(usr)
      @types.include?(usr) ||
        @structs.include?(usr) ||
        @enums.include?(usr) ||
        @unions.include?(usr)
    end

    def add_c_defs_used_by_decl(decl)
      case decl[:kind]
      when "ObjCInterface", "ObjCProtocol", "ObjCCategory"
        return if @types.include?(decl[:usr])
        @types << decl[:usr]
        if decl[:children]
          decl[:children].each do |child|
            add_c_defs_used_by_decl(child) if child[:kind] == "ObjCMethod"
          end
        end
      when "Typedef"
        add_c_defs_used_by_type(decl[:type])
      when "ObjCMethod"
        add_c_defs_used_by_type(decl[:return_type])
        decl[:params].each do |param|
          add_c_defs_used_by_type(param[:type])
        end
      when "Record"
        case decl[:tag_kind]
        when "struct"
          return if @structs.include?(decl[:usr])
          @structs << decl[:usr]
        when "union"
          return if @unions.include?(decl[:usr])
          @unions << decl[:usr]
        else
          raise "Unknown tag kind #{decl[:tag_kind]} in decl #{decl.inspect}"
        end
        decl[:fields].each do |field|
          add_c_defs_used_by_type(field[:type])
        end
      when "Field"
        add_c_defs_used_by_type(decl[:type])
      when "Enum"
        @enums << decl[:usr]
        add_c_defs_used_by_type(decl[:integer_type])
      when "ObjCInterface"
        @types << decl[:usr]
      else
        raise "Unknown decl #{decl.inspect}"
      end
    end

    def add_c_defs_used_by_type(type)
      case type[:type_class]
      when "Builtin", "ObjCTypeParam"
        nil
      when "Typedef", "Record", "Enum"
        decl = @converter.find_decl(type[:decl_usr])
        add_c_defs_used_by_decl(decl)
      when "Attributed"
        add_c_defs_used_by_type(type[:modified_type])
      when "Pointer", "Decayed", "ObjCObjectPointer", "BlockPointer"
        add_c_defs_used_by_type(type[:pointee])
      when "ObjCInterface", "ObjCObject"
        if type[:base_type]
          add_c_defs_used_by_type(type[:base_type])
        else
          decl = @converter.find_decl(type[:interface_usr])
          add_c_defs_used_by_decl(decl)
          if decl[:super_class_usr]
            super_class_decl = @converter.find_decl(decl[:super_class_usr])
            add_c_defs_used_by_decl(super_class_decl)
          end
        end
      when "ElaboratedType"
        add_c_defs_used_by_type(type[:named_type])
      when "FunctionProto"
        type[:params].each do |param|
          add_c_defs_used_by_type(param[:type])
        end
        add_c_defs_used_by_type(type[:return_type])
      when "FunctionNoProto"
        add_c_defs_used_by_type(type[:return_type])
      when "Paren"
        add_c_defs_used_by_type(type[:inner_type])
      when "ConstantArray"
        add_c_defs_used_by_type(type[:element_type])
      else
        raise "Unknown type #{type.inspect}"
      end
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

    # Make a list of the definitions used by Objective-C objects
    definitions_used = CDefinitionsSet.new(self)
    @json[:children].each do |decl|
      next if decl[:is_forward_declaration]
      next unless %w{ObjCInterface ObjCProtocol ObjCCategory}.include?(decl[:kind])
      definitions_used.add_c_defs_used_by_decl(decl)
    end

    @declarations_per_module = {}
    @selectors_per_module = {}
    @categories_per_module = {}
    @json[:children].each do |decl|
      next if decl[:is_forward_declaration]
      next unless %w{ObjCInterface ObjCProtocol ObjCCategory}.include?(decl[:kind]) || definitions_used.include?(decl[:usr])

      mod = determine_module(decl)

      @declarations_per_module[mod] ||= []
      @declarations_per_module[mod] << decl
      if %w{ObjCInterface ObjCProtocol ObjCCategory}.include?(decl[:kind])
        methods = decl[:children].select {|child| child[:kind] == "ObjCMethod" && method_handled?(child) }

        @selectors_per_module[mod] ||= Set.new
        @selectors_per_module[mod].merge methods.map {|method| method[:selector] }

        if decl[:kind] == "ObjCCategory"
          @categories_per_module[mod] ||= {}
          @categories_per_module[mod][decl[:class_name]] ||= []
          @categories_per_module[mod][decl[:class_name]] << decl
        end
      end
    end

    @declarations_per_module.each do |mod, decls|
      puts "mod #{mod} {"

      if mod == "core"
        puts <<-END
    pub type ObjCObjectPointer = *mut objc::runtime::Object;
    pub trait ObjCObject {
        fn ptr(&self) -> ObjCObjectPointer;
        fn from_ptr(ptr: ObjCObjectPointer) -> Self;
    }
        END
      end

      selectors = @selectors_per_module[mod]
      if selectors && !selectors.empty?
        puts <<-END
    #[allow(non_upper_case_globals)]
    mod selectors {
        use objc::runtime::Sel;

        lazy_static! {
        END
        selectors.to_a.sort.each do |selector|
          puts %{            pub static ref #{selector.gsub(":", "_")}: Sel = Sel::register("#{selector}");}
        end
        puts <<-END
        }
    }
        END
      end

      class_names = decls
        .select {|decl| decl[:kind] == "ObjCInterface" }
        .map {|decl| decl[:name] }

      unless class_names.empty?
        puts <<-END
    #[allow(non_upper_case_globals)]
    mod classes {
        use objc::runtime::Class;

        lazy_static! {
          END
        class_names.each do |name|
          puts %{            pub static ref #{name}: &'static Class = Class::get("#{name}").unwrap();}
        end
        puts <<-END
        }
    }
          END
      end

      decls.each do |decl|
        case decl[:kind]
        when "ObjCInterface"
          name = decl[:name]
          categories_on_class = @categories_per_module.dig(mod, name) || []
          followed_protocols = []
          followed_protocols.concat(decl[:protocols]) if decl[:protocols]
          followed_protocols.concat(categories_on_class.map do |category|
            category[:protocol] || []
          end.flatten)
          methods = []
          methods.concat(decl[:children].select {|child| child[:kind] == "ObjCMethod" })
          methods.concat(categories_on_class.map do |category|
            category[:children].select {|child| child[:kind] == "ObjCMethod" }
          end.flatten)

          raw_base_traits = []
          base_traits = []

          if decl[:super_class_usr]
            super_class_decl = find_decl(decl[:super_class_usr])
            raw_base_traits << "Raw#{super_class_decl[:name]}Interface"
            base_traits << "#{super_class_decl[:name]}Interface"
          end
          raw_base_traits.concat(followed_protocols.map {|protocol_name| "Raw#{protocol_name}Protocol" })
          base_traits.concat(followed_protocols.map {|protocol_name| "#{protocol_name}Protocol" })
          if base_traits.empty?
            base_traits << "ObjCObject"
            raw_base_traits << "ObjCObject"
          end

          puts "    pub struct #{name}(ObjCObjectPointer);"

          puts "    pub trait Raw#{name}Interface: #{raw_base_traits.join(", ")} {"
          methods.each do |method_decl|
            puts rustify_raw_method(method_decl)
          end
          puts "    }"

          puts "    pub trait #{name}Interface: #{base_traits.join(", ")} {"
          methods.each do |method_decl|
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

        when "ObjCProtocol"
          methods = decl[:children].select {|child| child[:kind] == "ObjCMethod" }
          followed_protocols = decl[:protocols] || []
          raw_base_traits = followed_protocols.map {|name| "Raw#{name}Protocol" }
          raw_base_traits << "ObjCObject" if raw_base_traits.empty?
          puts "    trait Raw#{decl[:name]}Protocol: #{raw_base_traits.join(", ")} {"
          methods.each do |method_decl|
            puts rustify_raw_method(method_decl)
          end
          puts "    }"

          base_traits = followed_protocols.map {|name| "#{name}Protocol" }
          base_traits << "ObjCObject" if raw_base_traits.empty?
          puts "    trait #{decl[:name]}Protocol: #{base_traits.join(", ")} {"
          methods.each do |method_decl|
            puts "        #{rustify_method(method_decl)}"
          end
          puts "    }"

        when "ObjCCategory"
          # If the class is defined in the module, the methods will be directly added to the class so nothing to do here
          class_name = decl[:class_name]
          class_mod = @class_module[class_name]
          next if mod == class_mod

          categories_on_same_class = @categories_per_module[mod][class_name]
          # We regroup all categories on the same class at the place the last category was defined in the module
          next unless categories_on_same_class.last[:usr] == decl[:usr]

          methods = categories_on_same_class.map do |category_decl|
            category_decl[:children].select {|child| child[:kind] == "ObjCMethod" }
          end.flatten
          followed_protocols = categories_on_same_class.map do |category_decl|
            category_decl[:protocols] || []
          end.flatten.uniq

          decl[:children].select {|child| child[:kind] == "ObjCMethod" }

          raw_base_traits = ["#{class_mod}::Raw#{class_name}Interface"]
          raw_base_traits.concat(followed_protocols.map {|protocol_name| "Raw#{protocol_name}Protocol" })
          puts "    trait Raw#{class_name}Category: #{raw_base_traits.join(", ")} {"
          methods.each do |method_decl|
            puts rustify_raw_method(method_decl)
          end
          puts "    }"

          base_traits = ["#{class_mod}::#{class_name}Interface"]
          base_traits.concat(followed_protocols.map {|protocol_name| "#{protocol_name}Protocol" })
          puts "    trait #{class_name}Category: #{base_traits.join(", ")} {"
          methods.each do |method_decl|
            puts "        #{rustify_method(method_decl)}"
          end
          puts "    }"
          puts "    impl #{class_name}Category for #{class_mod}::#{class_name} {}"

        else
          # TODO
        end
      end

      puts "}"
    end
  end
end