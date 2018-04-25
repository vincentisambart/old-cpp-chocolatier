require "pp"

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

  def ptr_to_id?(type)
    return false unless type[:type_class] == "ObjCObjectPointer" && type[:pointee][:type_class] == "ObjCObject"
    base_type = type[:pointee][:base_type]
    base_type && base_type[:type_class] == "Builtin" && base_type[:name] == "ObjCId"
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
      else
        raise "Unknown builtin type #{type.inspect}"
      end
    when "Typedef"
      decl = find_decl(type[:decl_usr])
      if type[:name] == "BOOL" && decl[:type][:type_class] == "Builtin" && decl[:type][:name] = "SChar"
        "objc::runtime::BOOL"
      elsif type[:name] == "instancetype" && ptr_to_id?(decl[:type])
        "Self"
      elsif type[:name] == "id" && ptr_to_id?(decl[:type])
        "id---TODO"
      elsif type[:name] == "SEL" && decl[:type][:type_class] == "Pointer" && decl[:type][:pointee][:type_class] == "Builtin" && decl[:type][:pointee][:name] = "ObjCSel"
        "objc::runtime::Sel"
      elsif type[:name] == "Class" && decl[:type][:type_class] == "ObjCObjectPointer" && decl[:type][:pointee][:type_class] == "ObjCObject" # TODO
        "Class---TODO"
# {:is_implicit=>true, :is_referenced=>false, :kind=>"Typedef", :name=>"Class", :type=>{:pointee=>{:base_type=>{:name=>"ObjCClass", :type_class=>"Builtin"}, :type_class=>"ObjCObject"}, :type_class=>"ObjCObjectPointer"}, :usr=>"c:@T@Class"}
      else
        "todo"
      end
    else
      "todo"
    end
  end

  def convert
    raise "Expecting a TranslationUnit declaration" unless @json[:kind] == "TranslationUnit"
    puts "extern crate objc;"
    puts "extern crate libc;"

    # A full declaration might come after its first use so make the list of all declarations first.
    @json[:children].each do |decl|
      p decl if decl[:is_implicit]
      @declarations[decl[:usr]] = decl unless decl[:is_forward_declaration]
    end

    @json[:children].each do |decl|
      next if decl[:is_forward_declaration] || decl[:is_implicit]
      next unless %w{ObjCInterface ObjCProtocol ObjCCategory}.include?(decl[:kind])

      base_traits = []
      if decl[:super_class_usr]
        super_class_decl = find_decl(decl[:super_class_usr])
        base_traits << "#{super_class_decl[:name]}Interface"
      end
      if decl[:protocols]
        base_traits.concat decl[:protocols].map {|protocol_name| "#{protocol_name}Protocol" }
      end

      case decl[:kind]
      when "ObjCProtocol"
        trait_name = "#{decl[:name]}Protocol"
      when "ObjCInterface"
        trait_name = "#{decl[:name]}Interface"
      when "ObjCCategory"
        trait_name = "#{decl[:class_name]}Category_#{decl[:name]}"
      end
      if base_traits.empty?
        puts "trait #{trait_name} {"
      else
        puts "trait #{trait_name}: #{base_traits.join(", ")} {"
      end
      decl[:children].each do |child|
        next unless child[:kind] == "ObjCMethod"
        method_name = child[:selector].gsub(":", "_")
        params = child[:params].map {|param| "#{param[:name]}: #{rustify_type(param[:type])}" }
        params.unshift("&self") if child[:is_instance_method]
        if void_type?(child[:return_type])
          puts "    fn #{method_name}(#{params.join(", ")})"
        else
          puts "    fn #{method_name}(#{params.join(", ")}) -> #{rustify_type(child[:return_type])}"
        end
        # pp child
      end
      puts "}"
      # pp decl
    end
  end
end