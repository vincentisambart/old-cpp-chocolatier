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

  def convert
    raise "Expecting a TranslationUnit declaration" unless @json[:kind] == "TranslationUnit"
    @json[:children].each do |decl|
      next if decl[:is_forward_declaration]
      @declarations[decl[:usr]] = decl
      next if decl[:is_implicit]
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
        puts "    fn #{child[:selector].gsub(":", "_")}"
      end
      puts "}"
      # pp decl
    end
  end
end