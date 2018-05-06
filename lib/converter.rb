require "pp"
require "set"

class Converter
  def initialize(json)
    @json = json
    @declarations = {}
  end

  def find_decl(usr)
    decl = @declarations[usr]
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
    when %r{/usr/include/(mach|sys)/.+\.h\z}, %r{/lib/clang/[^/]+/include/[^./]+\.h\z}, %r{/usr/include/MacTypes\.h\z}
      "core"
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

  def rustify_record(name, decl)
return if !decl[:fields] || name == "" # TODO
    raise "Tag kind #{decl[:tag_kind]} not yet supported in #{decl.inspect}" unless decl[:tag_kind] == "struct"
    puts "    #[repr(C)]"
    puts "    struct #{name} {"
    decl[:fields].each do |field|
      puts "        #{field[:name]}: #{rustify_raw_type(field[:type])},"
    end
    puts "    }"
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

  def definition_used?(usr)
    @definition_kinds.any? {|kind, set| set.include?(usr) }
  end

  def add_objc_defs_used_by_decl(decl)
    usr = decl[:usr]
    return if definition_used?(usr)
    case decl[:kind]
    when "ObjCInterface", "ObjCProtocol", "ObjCCategory"
      case decl[:kind]
      when "ObjCInterface"
        @definition_kinds[:types] << usr
      when "ObjCProtocol"
        @definition_kinds[:protocols] << usr
      when "ObjCCategory"
        @definition_kinds[:categories] << usr
      end
      if decl[:children]
        decl[:children].each do |child|
          add_objc_defs_used_by_decl(child) if child[:kind] == "ObjCMethod"
        end
      end
    when "Typedef"
      @definition_kinds[:types] << usr
      add_objc_defs_used_by_type(decl[:type])
    when "ObjCMethod"
      add_objc_defs_used_by_type(decl[:return_type])
      decl[:params].each do |param|
        add_objc_defs_used_by_type(param[:type])
      end
    when "Record"
      case decl[:tag_kind]
      when "struct"
        @definition_kinds[:structs] << usr
      when "union"
        @definition_kinds[:unions] << usr
      else
        raise "Unknown tag kind #{decl[:tag_kind]} in decl #{decl.inspect}"
      end
      if decl[:fields]
        decl[:fields].each do |field|
          add_objc_defs_used_by_type(field[:type])
        end
      end
    when "Field"
      add_objc_defs_used_by_type(decl[:type])
    when "Enum"
      @definition_kinds[:enums] << usr
      add_objc_defs_used_by_type(decl[:integer_type])
    when "ObjCInterface"
      @definition_kinds[:types] << usr
    else
      raise "Unknown decl #{decl.inspect}"
    end
  end

  def add_objc_defs_used_by_type(type)
    case type[:type_class]
    when "Builtin", "ObjCTypeParam"
      nil
    when "Typedef", "Record", "Enum"
      decl = find_decl(type[:decl_usr])
      add_objc_defs_used_by_decl(decl)
    when "Attributed"
      add_objc_defs_used_by_type(type[:modified_type])
    when "Pointer", "Decayed", "ObjCObjectPointer", "BlockPointer"
      add_objc_defs_used_by_type(type[:pointee])
    when "ObjCInterface", "ObjCObject"
      if type[:base_type]
        add_objc_defs_used_by_type(type[:base_type])
      else
        decl = find_decl(type[:interface_usr])
        add_objc_defs_used_by_decl(decl)
        if decl[:super_class_usr]
          super_class_decl = find_decl(decl[:super_class_usr])
          add_objc_defs_used_by_decl(super_class_decl)
        end
      end
    when "ElaboratedType"
      add_objc_defs_used_by_type(type[:named_type])
    when "FunctionProto"
      type[:params].each do |param|
        add_objc_defs_used_by_type(param[:type])
      end
      add_objc_defs_used_by_type(type[:return_type])
    when "FunctionNoProto"
      add_objc_defs_used_by_type(type[:return_type])
    when "Paren"
      add_objc_defs_used_by_type(type[:inner_type])
    when "ConstantArray"
      add_objc_defs_used_by_type(type[:element_type])
    when "ExtVector"
      # vector types are use by for example AVCameraCalibrationData (matrix_float)
      # For the time being not supported
    else
      raise "Unknown type #{type.inspect}"
    end
  end

  def protocol_trait_name(protocol, when_in:)
    mod = @protocol_module[protocol]
    if mod == when_in
      "#{protocol}Protocol"
    else
      "#{mod}::#{protocol}Protocol"
    end
  end

  def convert
    raise "Expecting a TranslationUnit declaration" unless @json[:kind] == "TranslationUnit"
    puts "extern crate objc;"
    puts "extern crate libc;"

    # A full declaration might come after its first use so make the list of all declarations first.
    @json[:children].each do |decl|
      usr = decl[:usr]
      known_decl = @declarations[usr]
      if known_decl
        next if decl[:is_forward_declaration]
        next if decl[:kind] == "Function" && decl[:is_implicit]
        next if decl[:kind] == "Typedef" && decl[:type] == known_decl[:type]

next if decl[:kind] == "Function" || decl[:kind] == "Var" # TODO
        raise "Multiple definitions of #{decl[:usr]}: #{decl.inspect} and #{@declarations[decl[:usr]].inspect}" unless known_decl[:is_forward_declaration]
      end

      @declarations[usr] = decl
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
    @definition_kinds = {}
    %i{types structs enums unions protocols categories}.each do |kind|
      @definition_kinds[kind] = Set.new
    end
    @json[:children].each do |decl|
      next if decl[:is_forward_declaration]
      next unless %w{ObjCInterface ObjCProtocol ObjCCategory}.include?(decl[:kind])
      add_objc_defs_used_by_decl(decl)
    end

    @declarations_per_module = {}
    @selectors_per_module = {}
    @categories_per_module = {}
    @elaborated_types_named_by_typedefs = {}
    @json[:children].each do |decl|
      next if decl[:is_forward_declaration]
      next unless definition_used?(decl[:usr])

      mod = determine_module(decl)

      @declarations_per_module[mod] ||= []
      @declarations_per_module[mod] << decl
      case decl[:kind]
      when "ObjCInterface", "ObjCProtocol", "ObjCCategory"
        methods = decl[:children].select {|child| child[:kind] == "ObjCMethod" && method_handled?(child) }

        @selectors_per_module[mod] ||= Set.new
        @selectors_per_module[mod].merge methods.map {|method| method[:selector] }

        if decl[:kind] == "ObjCCategory"
          @categories_per_module[mod] ||= {}
          @categories_per_module[mod][decl[:class_name]] ||= []
          @categories_per_module[mod][decl[:class_name]] << decl
        end
      when "Typedef"
        if %w{Record Enum}.include?(decl[:type][:type_class])
          elaborated_type_usr = decl[:type][:decl_usr]
          elaborated_type = find_decl(elaborated_type_usr)
          if decl[:name].gsub("_", "").downcase == elaborated_type[:name].gsub("_", "").downcase
            @elaborated_types_named_by_typedefs[elaborated_type_usr] = decl[:usr]
          end
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

          puts "    pub struct #{name}(ObjCObjectPointer);"

          puts "    pub trait Raw#{name}Interface: ObjCObject {"
          methods.each do |method_decl|
            puts rustify_raw_method(method_decl)
          end
          puts "    }"

          base_traits = ["Raw#{name}Interface"]
          if decl[:super_class_usr]
            super_class_decl = find_decl(decl[:super_class_usr])
            base_traits << "#{super_class_decl[:name]}Interface"
          end
          base_traits.concat(followed_protocols.map {|protocol| protocol_trait_name(protocol, when_in: mod) })

          puts "    pub trait #{name}Interface: #{base_traits.join(", ")} {"
          methods.each do |method_decl|
            puts "        #{rustify_method(method_decl)}"
          end
          puts "    }"

          # from_ptr_unchecked doesn't check if the class is correct, but it does check that the pointer is not null.
          puts <<-END
    impl ObjCObject for #{name} {
        fn ptr(&self) -> ObjCObjectPointer {
            self.0
        }
        fn from_ptr_unchecked(ptr: ObjCObjectPointer) -> Self {
            assert!(!ptr.is_null());
            #{name}(ptr)
        }
    }
          END
          puts "    impl #{name}Interface for #{name} {}"

        when "ObjCProtocol"
          methods = decl[:children].select {|child| child[:kind] == "ObjCMethod" }
          followed_protocols = decl[:protocols] || []

          puts "    trait Raw#{decl[:name]}Protocol: ObjCObject {"
          methods.each do |method_decl|
            puts rustify_raw_method(method_decl)
          end
          puts "    }"

          base_traits = ["Raw#{decl[:name]}Protocol"]
          base_traits.concat(followed_protocols.map {|protocol| protocol_trait_name(protocol, when_in: mod) })
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

          puts "    trait Raw#{class_name}Category: ObjCObject {"
          methods.each do |method_decl|
            puts rustify_raw_method(method_decl)
          end
          puts "    }"

          base_traits = [
            "#{class_mod}::#{class_name}Interface",
            "Raw#{class_name}Category",
          ]
          base_traits.concat(followed_protocols.map {|protocol| protocol_trait_name(protocol, when_in: mod) })
          puts "    trait #{class_name}Category: #{base_traits.join(", ")} {"
          methods.each do |method_decl|
            puts "        #{rustify_method(method_decl)}"
          end
          puts "    }"
          puts "    impl #{class_name}Category for #{class_mod}::#{class_name} {}"

        when "Record"
          next if @elaborated_types_named_by_typedefs[decl[:usr]]
          rustify_record(decl[:name], decl)

        when "Enum"
          next if @elaborated_types_named_by_typedefs[decl[:usr]]
          # TODO

        when "Typedef"
          case decl[:type][:type_class]
          when "Record"
            record_usr = decl[:type][:decl_usr]
            if @elaborated_types_named_by_typedefs[record_usr] == decl[:usr]
              rustify_record(decl[:name], find_decl(record_usr))
            else
              # TODO
            end
          else
            # TODO
          end

        else
          raise "Unknown decl #{decl.inspect}"
        end
      end

      puts "}"
    end
  end
end