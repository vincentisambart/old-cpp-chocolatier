#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcovered-switch-default"
#include "json.hpp"
#pragma clang diagnostic pop

#include "clang/AST/ASTConsumer.h"
#include "clang/AST/RecursiveASTVisitor.h"
#include "clang/Basic/Version.h"
#include "clang/Frontend/CompilerInstance.h"
#include "clang/Frontend/FrontendAction.h"
#include "clang/Index/USRGeneration.h"
#include "clang/Tooling/CommonOptionsParser.h"
#include "clang/Tooling/Tooling.h"
#include "llvm/Support/raw_os_ostream.h"

#include <iostream>
#include <memory>

auto serialize_type(clang::Type const *type, clang::ASTContext const *context) -> nlohmann::json;
auto serialize_type(clang::QualType const &qual_type, clang::ASTContext const *context)
    -> nlohmann::json;
auto serialize_decl(clang::Decl const *decl) -> nlohmann::json;

auto get_builtin_kind_name(clang::BuiltinType::Kind kind) -> char const * {
  switch (kind) {
  case clang::BuiltinType::Void:
    return "Void";
  case clang::BuiltinType::Bool:
    return "Bool";
  case clang::BuiltinType::Char_U:
    return "Char_U";
  case clang::BuiltinType::UChar:
    return "UChar";
  case clang::BuiltinType::WChar_U:
    return "WChar_U";
  case clang::BuiltinType::Char16:
    return "Char16";
  case clang::BuiltinType::Char32:
    return "Char32";
  case clang::BuiltinType::UShort:
    return "UShort";
  case clang::BuiltinType::UInt:
    return "UInt";
  case clang::BuiltinType::ULong:
    return "ULong";
  case clang::BuiltinType::ULongLong:
    return "ULongLong";
  case clang::BuiltinType::UInt128:
    return "UInt128";
  case clang::BuiltinType::Char_S:
    return "Char_S";
  case clang::BuiltinType::SChar:
    return "SChar";
  case clang::BuiltinType::WChar_S:
    return "WChar_S";
  case clang::BuiltinType::Short:
    return "Short";
  case clang::BuiltinType::Int:
    return "Int";
  case clang::BuiltinType::Long:
    return "Long";
  case clang::BuiltinType::LongLong:
    return "LongLong";
  case clang::BuiltinType::Int128:
    return "Int128";
  case clang::BuiltinType::Float:
    return "Float";
  case clang::BuiltinType::Double:
    return "Double";
  case clang::BuiltinType::LongDouble:
    return "LongDouble";
#if CLANG_VERSION_MAJOR >= 6
  case clang::BuiltinType::Float16:
    return "Float16";
#endif
  case clang::BuiltinType::Float128:
    return "Float128";
  case clang::BuiltinType::ObjCId:
    return "ObjCId";
  case clang::BuiltinType::ObjCClass:
    return "ObjCClass";
  case clang::BuiltinType::ObjCSel:
    return "ObjCSel";
  default:
    std::cerr << "Unknown builtin type: " << kind << "\n";
    return "unknown";
  }
}

auto get_method_family_name(clang::ObjCMethodFamily family) -> char const * {
  switch (family) {
  case clang::OMF_None:
    return nullptr;
  case clang::OMF_alloc:
    return "alloc";
  case clang::OMF_copy:
    return "copy";
  case clang::OMF_init:
    return "init";
  case clang::OMF_mutableCopy:
    return "mutableCopy";
  case clang::OMF_new:
    return "new";
  case clang::OMF_autorelease:
    return "autorelease";
  case clang::OMF_dealloc:
    return "dealloc";
  case clang::OMF_finalize:
    return "finalize";
  case clang::OMF_release:
    return "release";
  case clang::OMF_retain:
    return "retain";
  case clang::OMF_retainCount:
    return "retainCount";
  case clang::OMF_self:
    return "self";
  case clang::OMF_initialize:
    return "initialize";
  case clang::OMF_performSelector:
    return "performSelector";
  }
}

auto generate_usr_for_decl(clang::Decl const *decl) -> llvm::SmallString<128> {
  llvm::SmallString<128> usr;
  clang::index::generateUSRForDecl(decl, usr);
  return usr;
}

auto serialize_type(clang::Type const *type, clang::ASTContext const *context) -> nlohmann::json {
  nlohmann::json serialized_type;

  // {
  //   llvm::raw_os_ostream err{std::cerr};
  //   err << "Type class " << type->getTypeClassName() << "\n";
  // }
  serialized_type["type_class"] = type->getTypeClassName();

  switch (type->getTypeClass()) {
  case clang::Type::ObjCObjectPointer: {
    auto objc_obj_ptr_type = static_cast<const clang::ObjCObjectPointerType *>(type);
    auto pointee = objc_obj_ptr_type->getPointeeType();
    serialized_type["pointee"] = serialize_type(pointee, context);
  } break;
  case clang::Type::Builtin: {
    auto builtin_type = static_cast<const clang::BuiltinType *>(type);
    serialized_type["name"] = get_builtin_kind_name(builtin_type->getKind());
  } break;
  case clang::Type::Pointer: {
    auto ptr_type = static_cast<const clang::PointerType *>(type);
    auto pointee = ptr_type->getPointeeType();
    serialized_type["pointee"] = serialize_type(pointee, context);
  } break;
  case clang::Type::BlockPointer: {
    auto block_ptr_type = static_cast<const clang::BlockPointerType *>(type);
    auto pointee = block_ptr_type->getPointeeType();
    serialized_type["pointee"] = serialize_type(pointee, context);
  } break;
  case clang::Type::ConstantArray: {
    auto constant_array_type = static_cast<const clang::ConstantArrayType *>(type);
    serialized_type["size"] = constant_array_type->getSize().getZExtValue();
    serialized_type["element_type"] =
        serialize_type(constant_array_type->getElementType(), context);
  } break;
  case clang::Type::IncompleteArray: {
    auto incomplete_array_type = static_cast<const clang::IncompleteArrayType *>(type);
    serialized_type["element_type"] =
        serialize_type(incomplete_array_type->getElementType(), context);
  } break;
  case clang::Type::FunctionProto: {
    auto function_proto_type = static_cast<const clang::FunctionProtoType *>(type);
    serialized_type["is_variadic"] = function_proto_type->isVariadic();
    serialized_type["return_type"] = serialize_type(function_proto_type->getReturnType(), context);
    {
      auto serialized_params = nlohmann::json::array();
      auto num_params = function_proto_type->getNumParams();
      for (unsigned i = 0; i < num_params; ++i) {
        nlohmann::json serialized_param;
        serialized_param["type"] = serialize_type(function_proto_type->getParamType(i), context);
        if (function_proto_type->isParamConsumed(i)) {
          serialized_param["is_consumed"] = true;
        }
        serialized_params.push_back(std::move(serialized_param));
      }
      serialized_type["params"] = std::move(serialized_params);
    }
  } break;
  case clang::Type::FunctionNoProto: {
    auto function_no_proto_type = static_cast<const clang::FunctionNoProtoType *>(type);
    serialized_type["return_type"] =
        serialize_type(function_no_proto_type->getReturnType(), context);
  } break;
  case clang::Type::Paren: {
    auto paren_type = static_cast<const clang::ParenType *>(type);
    auto inner = paren_type->getInnerType();
    serialized_type["inner_type"] = serialize_type(inner, context);
  } break;
  case clang::Type::Typedef: {
    auto typedef_type = static_cast<const clang::TypedefType *>(type);
    auto decl = typedef_type->getDecl();
    serialized_type["name"] = decl->getName();
    serialized_type["decl_usr"] = generate_usr_for_decl(decl).str();
  } break;
  case clang::Type::Decayed: {
    auto decayed_type = static_cast<const clang::DecayedType *>(type);
    auto pointee = decayed_type->getPointeeType();
    serialized_type["pointee"] = serialize_type(pointee, context);
  } break;
  case clang::Type::Record: {
    auto record_type = static_cast<const clang::RecordType *>(type);
    // A struct can contain a reference to itself so we cannot expand the decl
    serialized_type["decl_usr"] = generate_usr_for_decl(record_type->getDecl()).str();
  } break;
  case clang::Type::Enum: {
    auto enum_type = static_cast<const clang::EnumType *>(type);
    serialized_type["decl_usr"] = generate_usr_for_decl(enum_type->getDecl()).str();
  } break;
  case clang::Type::Elaborated: {
    auto elaborated_type = static_cast<const clang::ElaboratedType *>(type);
    serialized_type["type_class"] = "ElaboratedType";
    serialized_type["keyword"] =
        clang::ElaboratedType::getKeywordName(elaborated_type->getKeyword());
    serialized_type["named_type"] = serialize_type(elaborated_type->getNamedType(), context);
  } break;
  case clang::Type::Attributed: {
    auto attributed_type = static_cast<const clang::AttributedType *>(type);
    serialized_type["modified_type"] = serialize_type(attributed_type->getModifiedType(), context);
    nlohmann::json attributes;
    switch (attributed_type->getAttrKind()) {
    case clang::AttributedType::Kind::attr_nonnull:
      serialized_type["nullability"] = "nonnull";
      break;
    case clang::AttributedType::Kind::attr_nullable:
      serialized_type["nullability"] = "nullable";
      break;
    case clang::AttributedType::Kind::attr_ns_returns_retained:
      serialized_type["ns_returns_retained"] = true;
      break;
    default:
      break;
    }
  } break;
  case clang::Type::ObjCTypeParam: {
    auto objc_type_param = static_cast<const clang::ObjCTypeParamType *>(type);
    auto decl = objc_type_param->getDecl();
    serialized_type["name"] = decl->getName();
    {
      nlohmann::json protocols;
      for (auto const protocol : objc_type_param->getProtocols()) {
        protocols.push_back(protocol->getName());
      }
      if (!protocols.empty()) {
        serialized_type["protocols"] = protocols;
      }
    }
  } break;
  case clang::Type::ObjCInterface:
  case clang::Type::ObjCObject: {
    auto objc_obj_type = static_cast<const clang::ObjCObjectType *>(type);
    auto base_type = objc_obj_type->getBaseType();
    if (base_type->isBuiltinType()) {
      serialized_type["base_type"] = serialize_type(base_type, context);
    }
    auto interface = objc_obj_type->getInterface();
    if (interface != nullptr) {
      serialized_type["interface_usr"] = generate_usr_for_decl(interface).str();
    }
    {
      nlohmann::json protocols;
      for (auto const protocol : objc_obj_type->getProtocols()) {
        protocols.push_back(protocol->getName());
      }
      if (!protocols.empty()) {
        serialized_type["protocols"] = protocols;
      }
    }
    {
      nlohmann::json type_args;
      for (auto const &type_arg : objc_obj_type->getTypeArgs()) {
        type_args.push_back(serialize_type(type_arg, context));
      }
      if (!type_args.empty()) {
        serialized_type["type_args"] = type_args;
      }
    }
  } break;
  case clang::Type::Vector:
  case clang::Type::ExtVector: {
    auto vector_type = static_cast<const clang::VectorType *>(type);
    serialized_type["num_elements"] = vector_type->getNumElements();
    serialized_type["element_type"] = serialize_type(vector_type->getElementType(), context);
  } break;
  default: {
    llvm::raw_os_ostream err{std::cerr};
    err << "Unknown type class " << type->getTypeClassName() << "\n";
  } break;
  }

  return serialized_type;
}

auto serialize_type(clang::QualType const &qual_type, clang::ASTContext const *context)
    -> nlohmann::json {
  return serialize_type(qual_type.getTypePtr(), context);
}

auto serialize_decl_children(clang::DeclContext const *decl_context) -> nlohmann::json {
  auto children = nlohmann::json::array();
  for (auto const child_decl : decl_context->decls()) {
    auto child = serialize_decl(child_decl);
    if (!child.is_null()) {
      children.push_back(child);
    }
  }
  return children;
}

template <class DeclType>
auto add_protocols_if_any(nlohmann::json &serialized_decl, DeclType *decl) -> void {
  {
    nlohmann::json protocols;
    for (auto const protocol : decl->protocols()) {
      protocols.push_back(protocol->getName());
    }
    if (!protocols.empty()) {
      serialized_decl["protocols"] = protocols;
    }
  }
}

auto serialize_decl(clang::Decl const *decl) -> nlohmann::json {
  // We don't care about empty declarations
  if (decl->getKind() == clang::Decl::Empty) {
    return nullptr;
  }

  auto context = &decl->getASTContext();
  nlohmann::json serialized_decl;

  serialized_decl["kind"] = decl->getDeclKindName();
  serialized_decl["is_implicit"] = decl->isImplicit();
  serialized_decl["is_referenced"] = decl->isReferenced();
  serialized_decl["usr"] = generate_usr_for_decl(decl).str();
  {
    auto location = decl->getLocation();
    if (location.isValid()) {
      auto const &source_manager = context->getSourceManager();
      auto presumed_loc = source_manager.getPresumedLoc(location);
      if (!presumed_loc.isInvalid()) {
        nlohmann::json serialized_location;
        serialized_location["file"] = presumed_loc.getFilename();
        serialized_location["line"] = presumed_loc.getLine();
        serialized_decl["location"] = serialized_location;
      }
    }
  }

  // {
  //   llvm::raw_os_ostream err{std::cerr};
  //   err << "Decl kind " << decl->getDeclKindName() << " for:";
  //   decl->print(err);
  //   err << "\n";
  // }

  switch (decl->getKind()) {
  case clang::Decl::Typedef: {
    auto typedef_decl = static_cast<const clang::TypedefDecl *>(decl);
    serialized_decl["name"] = typedef_decl->getName();
    auto typedef_type = context->getTypedefType(typedef_decl);
    serialized_decl["type"] = serialize_type(typedef_type.getCanonicalType(), context);
  } break;
  case clang::Decl::ObjCInterface: {
    auto objc_interface_decl = static_cast<const clang::ObjCInterfaceDecl *>(decl);
    serialized_decl["name"] = objc_interface_decl->getName();
    bool is_forward_declaration = objc_interface_decl->getDefinition() != objc_interface_decl;
    serialized_decl["is_forward_declaration"] = is_forward_declaration;
    if (!is_forward_declaration) {
      serialized_decl["children"] = serialize_decl_children(objc_interface_decl);
    }
    add_protocols_if_any(serialized_decl, objc_interface_decl);
    auto super_class = objc_interface_decl->getSuperClass();
    if (super_class != nullptr) {
      serialized_decl["super_class_usr"] = generate_usr_for_decl(super_class).str();
    }
    auto type_param_list = objc_interface_decl->getTypeParamList();
    if (type_param_list != nullptr) {
      nlohmann::json type_params;
      for (auto const type_param : *type_param_list) {
        type_params.push_back(type_param->getName());
      }
      if (!type_params.empty()) {
        serialized_decl["type_params"] = type_params;
      }
    }
  } break;
  case clang::Decl::ObjCProtocol: {
    auto objc_protocol_decl = static_cast<const clang::ObjCProtocolDecl *>(decl);
    serialized_decl["name"] = objc_protocol_decl->getName();
    bool is_forward_declaration = objc_protocol_decl->getDefinition() != objc_protocol_decl;
    serialized_decl["is_forward_declaration"] = is_forward_declaration;
    if (!is_forward_declaration) {
      serialized_decl["children"] = serialize_decl_children(objc_protocol_decl);
    }
    add_protocols_if_any(serialized_decl, objc_protocol_decl);
  } break;
  case clang::Decl::ObjCCategory: {
    auto objc_category_decl = static_cast<const clang::ObjCCategoryDecl *>(decl);
    auto class_interface = objc_category_decl->getClassInterface();
    serialized_decl["name"] = objc_category_decl->getName();
    serialized_decl["class_name"] = class_interface->getName();
    serialized_decl["children"] = serialize_decl_children(objc_category_decl);
    add_protocols_if_any(serialized_decl, objc_category_decl);
  } break;
  case clang::Decl::ObjCMethod: {
    nlohmann::json decl_attrs;
    auto objc_method_decl = static_cast<const clang::ObjCMethodDecl *>(decl);
    serialized_decl["selector"] = objc_method_decl->getSelector().getAsString();
    serialized_decl["is_instance_method"] = objc_method_decl->isInstanceMethod();
    auto method_family_name = get_method_family_name(objc_method_decl->getMethodFamily());
    if (method_family_name != nullptr) {
      serialized_decl["method_family"] = method_family_name;
    }
    serialized_decl["is_variadic"] = objc_method_decl->isVariadic();
    {
      auto serialized_params = nlohmann::json::array();
      for (auto const parm_decl : objc_method_decl->parameters()) {
        nlohmann::json serialized_param;
        nlohmann::json param_attrs;
        serialized_param["name"] = parm_decl->getName();
        serialized_param["type"] = serialize_type(parm_decl->getType(), context);
        if (parm_decl->hasAttr<clang::NSConsumedAttr>()) {
          param_attrs["is_consumed"] = true;
        }
        if (!param_attrs.empty()) {
          serialized_param["attrs"] = param_attrs;
        }
        serialized_params.push_back(std::move(serialized_param));
      }
      serialized_decl["params"] = std::move(serialized_params);
    }
    if (objc_method_decl->hasAttr<clang::NSConsumesSelfAttr>()) {
      decl_attrs["self_is_consumed"] = true;
    }
    if (objc_method_decl->hasAttr<clang::NSReturnsRetainedAttr>()) {
      decl_attrs["ns_returns_retained"] = true;
    }
    serialized_decl["return_type"] = serialize_type(objc_method_decl->getReturnType(), context);
    switch (objc_method_decl->getImplementationControl()) {
    case clang::ObjCMethodDecl::Optional:
      serialized_decl["implementation_control"] = "optional";
      break;
    case clang::ObjCMethodDecl::Required:
      serialized_decl["implementation_control"] = "required";
      break;
    default:
      break;
    }
    if (!decl_attrs.empty()) {
      serialized_decl["attrs"] = decl_attrs;
    }
  } break;
  case clang::Decl::Record: {
    auto record_decl = static_cast<const clang::RecordDecl *>(decl);
    serialized_decl["name"] = record_decl->getName();
    {
      auto fields = nlohmann::json::array();
      for (auto const field_decl : record_decl->fields()) {
        // All enumerators should be instances of EnumConstantDecl
        fields.push_back(serialize_decl(field_decl));
      }
      serialized_decl["fields"] = std::move(fields);
    }
    serialized_decl["tag_kind"] = record_decl->getKindName();
  } break;
  case clang::Decl::Enum: {
    auto enum_decl = static_cast<const clang::EnumDecl *>(decl);
    serialized_decl["name"] = enum_decl->getName();
    serialized_decl["is_closed"] = enum_decl->isClosed();
    auto integer_type = enum_decl->getIntegerType();
    if (!integer_type.isNull()) {
      serialized_decl["integer_type"] = serialize_type(integer_type, context);
    }
    {
      auto enumerators = nlohmann::json::array();
      for (auto const enumerator_decl : enum_decl->enumerators()) {
        // All enumerators should be instances of EnumConstantDecl
        enumerators.push_back(serialize_decl(enumerator_decl));
      }
      serialized_decl["enumerators"] = std::move(enumerators);
    }
  } break;
  case clang::Decl::EnumConstant: {
    auto enum_constant_decl = static_cast<const clang::EnumConstantDecl *>(decl);
    serialized_decl["name"] = enum_constant_decl->getName();
    auto qual_type = enum_constant_decl->getType();
    // JSON's precision of numbers doesn't seem to be well defined so to be sure we keep the full
    // precision store them as decimal strings.
    if (qual_type->isSignedIntegerType()) {
      serialized_decl["value"] = enum_constant_decl->getInitVal().toString(10, true);
    } else if (qual_type->isUnsignedIntegerType()) {
      serialized_decl["value"] = enum_constant_decl->getInitVal().toString(10, false);
    } else {
      llvm::raw_os_ostream err{std::cerr};
      err << "\n";
      err << "Could not find if ";
      qual_type.print(err, context->getPrintingPolicy());
      err << " is signed or not\n";
    }
  } break;
  case clang::Decl::Field: {
    auto field_decl = static_cast<const clang::FieldDecl *>(decl);
    serialized_decl["name"] = field_decl->getName();
    serialized_decl["type"] = serialize_type(field_decl->getType(), context);
    if (field_decl->isBitField()) {
      serialized_decl["bit_width"] = field_decl->getBitWidthValue(*context);
    }
  } break;
  case clang::Decl::Var: {
    auto var_decl = static_cast<const clang::VarDecl *>(decl);
    serialized_decl["name"] = var_decl->getName();
    serialized_decl["type"] = serialize_type(var_decl->getType(), context);
  } break;
  case clang::Decl::Function: {
    nlohmann::json decl_attrs;
    auto function_decl = static_cast<const clang::FunctionDecl *>(decl);
    serialized_decl["name"] = function_decl->getName();
    serialized_decl["type"] = serialize_type(function_decl->getType(), context);
    serialized_decl["is_variadic"] = function_decl->isVariadic();
    {
      auto serialized_params = nlohmann::json::array();
      for (auto const parm_var_decl : function_decl->parameters()) {
        nlohmann::json serialized_param;
        nlohmann::json param_attrs;
        serialized_param["name"] = parm_var_decl->getName();
        serialized_param["type"] = serialize_type(parm_var_decl->getType(), context);
        if (parm_var_decl->hasAttr<clang::NSConsumedAttr>()) {
          param_attrs["is_consumed"] = true;
        }
        if (!param_attrs.empty()) {
          serialized_param["attrs"] = param_attrs;
        }
        serialized_params.push_back(std::move(serialized_param));
      }
      serialized_decl["params"] = std::move(serialized_params);
    }
    serialized_decl["has_body"] = function_decl->hasBody();
    if (function_decl->hasAttr<clang::NSReturnsRetainedAttr>()) {
      decl_attrs["ns_returns_retained"] = true;
    }
    if (!decl_attrs.empty()) {
      serialized_decl["attrs"] = decl_attrs;
    }
  } break;
  case clang::Decl::ObjCIvar: {
    auto objc_ivar_decl = static_cast<const clang::ObjCIvarDecl *>(decl);
    serialized_decl["name"] = objc_ivar_decl->getName();
    serialized_decl["type"] = serialize_type(objc_ivar_decl->getType(), context);
  } break;
  case clang::Decl::ObjCProperty: {
    auto objc_property_decl = static_cast<const clang::ObjCPropertyDecl *>(decl);
    serialized_decl["name"] = objc_property_decl->getName();
    serialized_decl["type"] = serialize_type(objc_property_decl->getType(), context);
    switch (objc_property_decl->getPropertyImplementation()) {
    case clang::ObjCPropertyDecl::Optional:
      serialized_decl["property_implementation"] = "optional";
      break;
    case clang::ObjCPropertyDecl::Required:
      serialized_decl["property_implementation"] = "required";
      break;
    default:
      break;
    }
    // TODO: Should get more info about property
  } break;
  default: {
    llvm::raw_os_ostream err{std::cerr};
    err << "Unknown decl kind " << decl->getDeclKindName() << " for:";
    decl->print(err);
    err << "\n";
    return nullptr;
  } break;
  }

  return serialized_decl;
}

auto serialize_translation_unit_decl(clang::TranslationUnitDecl const *tu_decl) -> nlohmann::json {
  nlohmann::json serialized_tu;
  serialized_tu["kind"] = "TranslationUnit";
  auto children = serialize_decl_children(tu_decl);
  // For some reason the implicit declarations at the start of TU contain id, SEL, Class, but not
  // instancetype so we have to add it by hand.
  auto serialized_instance_type_decl =
      serialize_decl(tu_decl->getASTContext().getObjCInstanceTypeDecl());
  children.insert(children.begin(), serialized_instance_type_decl);
  serialized_tu["children"] = children;
  return serialized_tu;
}

class JSONSerializerASTConsumer : public clang::ASTConsumer {
public:
  explicit JSONSerializerASTConsumer(clang::ASTContext *context) {}
  virtual auto HandleTranslationUnit(clang::ASTContext &context) -> void override {
    if (context.getDiagnostics().hasErrorOccurred()) {
      return;
    }
    auto json = serialize_translation_unit_decl(context.getTranslationUnitDecl());
    std::cout << std::setw(4) << json << std::endl;
  }
};

class JSONSerializerFrontendAction : public clang::ASTFrontendAction {
public:
  virtual auto CreateASTConsumer(clang::CompilerInstance &ci, StringRef file)
      -> std::unique_ptr<clang::ASTConsumer> override {
    return std::make_unique<JSONSerializerASTConsumer>(&ci.getASTContext());
  }
};

static llvm::cl::OptionCategory JSONSerializerCategory("JSON serializer options");

auto main(int argc, const char **argv) -> int {
  clang::tooling::CommonOptionsParser op(argc, argv, JSONSerializerCategory);
  clang::tooling::ClangTool tool(op.getCompilations(), op.getSourcePathList());
  return tool.run(clang::tooling::newFrontendActionFactory<JSONSerializerFrontendAction>().get());
}