/******************************************************************************
 * Copyright 2018 The Apollo Authors. All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *****************************************************************************/

#ifndef CYBER_CLASS_LOADER_UTILITY_CLASS_LOADER_UTILITY_H_
#define CYBER_CLASS_LOADER_UTILITY_CLASS_LOADER_UTILITY_H_

#include <cassert>
#include <cstdio>

#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <typeinfo>
#include <utility>
#include <vector>

#include "cyber/class_loader/shared_library/shared_library.h"
#include "cyber/class_loader/utility/class_factory.h"
#include "cyber/common/log.h"

/**
 *  class register implement
 */
namespace apollo {
namespace cyber {
namespace class_loader {

class ClassLoader;

namespace utility {

using SharedLibraryPtr = std::shared_ptr<SharedLibrary>;
using ClassClassFactoryMap =
    std::map<std::string, utility::AbstractClassFactoryBase*>;
using BaseToClassFactoryMapMap = std::map<std::string, ClassClassFactoryMap>;
using LibPathSharedLibVector =
    std::vector<std::pair<std::string, SharedLibraryPtr>>;
using ClassFactoryVector = std::vector<AbstractClassFactoryBase*>;

BaseToClassFactoryMapMap& GetClassFactoryMapMap();
std::recursive_mutex& GetClassFactoryMapMapMutex();
LibPathSharedLibVector& GetLibPathSharedLibVector();
std::recursive_mutex& GetLibPathSharedLibMutex();
ClassClassFactoryMap& GetClassFactoryMapByBaseClass(
    const std::string& typeid_base_class_name);
std::string GetCurLoadingLibraryName();
void SetCurLoadingLibraryName(const std::string& library_name);
ClassLoader* GetCurActiveClassLoader();
void SetCurActiveClassLoader(ClassLoader* loader);
bool IsLibraryLoaded(const std::string& library_path, ClassLoader* loader);
bool IsLibraryLoadedByAnybody(const std::string& library_path);
bool LoadLibrary(const std::string& library_path, ClassLoader* loader);
void UnloadLibrary(const std::string& library_path, ClassLoader* loader);
template <typename Derived, typename Base>
void RegisterClass(const std::string& class_name,
                   const std::string& base_class_name);
template <typename Base>
Base* CreateClassObj(const std::string& class_name, ClassLoader* loader);
template <typename Base>
std::vector<std::string> GetValidClassNames(ClassLoader* loader);

// Register a class with the class factory system.
// This function creates a new class factory object for the derived class
// and associates it with the specified base class.
// The class factory object is then added to the class factory map for the
// base class, and the current loading library name is set.
template <typename Derived, typename Base>
void RegisterClass(const std::string& class_name,
                   const std::string& base_class_name) {
  AINFO << "registerclass:" << class_name << "," << base_class_name << ","
        << GetCurLoadingLibraryName();

  utility::AbstractClassFactory<Base>* new_class_factory_obj =
      new utility::ClassFactory<Derived, Base>(class_name, base_class_name);
  new_class_factory_obj->AddOwnedClassLoader(GetCurActiveClassLoader());
  new_class_factory_obj->SetRelativeLibraryPath(GetCurLoadingLibraryName());

  GetClassFactoryMapMapMutex().lock();
  ClassClassFactoryMap& factory_map =
      GetClassFactoryMapByBaseClass(typeid(Base).name());
  factory_map[class_name] = new_class_factory_obj;
  GetClassFactoryMapMapMutex().unlock();
}

/// Create an instance of the class specified by class_name
/// using the class factory registered for the base class Base.
/// Returns a pointer to the created object, or nullptr if the class
/// factory for the specified class_name does not exist or is not owned by the
/// provided ClassLoader.
template <typename Base>
Base* CreateClassObj(const std::string& class_name, ClassLoader* loader) {
  GetClassFactoryMapMapMutex().lock();
  ClassClassFactoryMap& factoryMap =
      GetClassFactoryMapByBaseClass(typeid(Base).name());
  AbstractClassFactory<Base>* factory = nullptr;
  if (factoryMap.find(class_name) != factoryMap.end()) {
    factory = dynamic_cast<utility::AbstractClassFactory<Base>*>(
        factoryMap[class_name]);
  }
  GetClassFactoryMapMapMutex().unlock();
  // Check if the factory is valid and owned by the loader
  Base* classobj = nullptr;
  if (factory && factory->IsOwnedBy(loader)) {
    classobj = factory->CreateObj();
  }

  return classobj;
}

/// Get a list of valid class names for the specified base class.
/// This function retrieves all class names registered with the class factory
/// system for the base class Base, and filters them to include only those
/// that are owned by the specified ClassLoader.
template <typename Base>
std::vector<std::string> GetValidClassNames(ClassLoader* loader) {
  std::lock_guard<std::recursive_mutex> lck(GetClassFactoryMapMapMutex());

  ClassClassFactoryMap& factoryMap =
      GetClassFactoryMapByBaseClass(typeid(Base).name());
  std::vector<std::string> classes;
  for (auto& class_factory : factoryMap) {
    AbstractClassFactoryBase* factory = class_factory.second;
    if (factory && factory->IsOwnedBy(loader)) {
      classes.emplace_back(class_factory.first);
    }
  }

  return classes;
}

}  // namespace utility
}  // namespace class_loader
}  // namespace cyber
}  // namespace apollo

#endif  // CYBER_CLASS_LOADER_UTILITY_CLASS_LOADER_UTILITY_H_
