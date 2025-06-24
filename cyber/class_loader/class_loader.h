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
#ifndef CYBER_CLASS_LOADER_CLASS_LOADER_H_
#define CYBER_CLASS_LOADER_CLASS_LOADER_H_

#include <algorithm>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "cyber/class_loader/class_loader_register_macro.h"

namespace apollo {
namespace cyber {
namespace class_loader {

/**
 *  for library load,createclass object
 */
class ClassLoader {
 public:
  explicit ClassLoader(const std::string& library_path);
  virtual ~ClassLoader();

  bool IsLibraryLoaded(); //Is the library loaded?
  bool LoadLibrary();//Load the library
  int UnloadLibrary();//unload the library
  const std::string GetLibraryPath() const; //Get the library path

  //Get the valid class names for a specific base class
  template <typename Base>
  std::vector<std::string> GetValidClassNames();

 // Create an object of a specific class name derived from Base
  template <typename Base>
  std::shared_ptr<Base> CreateClassObj(const std::string& class_name); 

  // Check if a class name is valid for a specific base class
  template <typename Base>
  bool IsClassValid(const std::string& class_name);

 private:
 // Deleter for class objects created by CreateClassObj 
  template <typename Base>
  void OnClassObjDeleter(Base* obj);

 private:
  std::string library_path_; // Path to the library
  int loadlib_ref_count_; // Reference count for the library load
  std::mutex loadlib_ref_count_mutex_; //Class loading reference count lock
  int classobj_ref_count_; // Reference count for class objects created
  std::mutex classobj_ref_count_mutex_; //Class object reference count lock
};

template <typename Base>
std::vector<std::string> ClassLoader::GetValidClassNames() {
  return (utility::GetValidClassNames<Base>(this));
}

template <typename Base>
bool ClassLoader::IsClassValid(const std::string& class_name) {
  std::vector<std::string> valid_classes = GetValidClassNames<Base>();
  return (std::find(valid_classes.begin(), valid_classes.end(), class_name) !=
          valid_classes.end());
}

template <typename Base>
std::shared_ptr<Base> ClassLoader::CreateClassObj(
    const std::string& class_name) {
      //load the library if not loaded
  if (!IsLibraryLoaded()) {
    LoadLibrary();
  }

  Base* class_object = utility::CreateClassObj<Base>(class_name, this); // Create an object of the class with the given name
  if (class_object == nullptr) {
    AWARN << "CreateClassObj failed, ensure class has been registered. "
          << "classname: " << class_name << ",lib: " << GetLibraryPath();
    return std::shared_ptr<Base>();
  }

  // Increment the reference count for class objects
  std::lock_guard<std::mutex> lck(classobj_ref_count_mutex_); 
  classobj_ref_count_ = classobj_ref_count_ + 1;
  // Create a shared pointer with a custom deleter that decrements the reference count
  // when the object is deleted
  std::shared_ptr<Base> classObjSharePtr(
      class_object, std::bind(&ClassLoader::OnClassObjDeleter<Base>, this,
                              std::placeholders::_1));
  return classObjSharePtr;
}

template <typename Base>
void ClassLoader::OnClassObjDeleter(Base* obj) {
  if (nullptr == obj) {
    return;
  }

  delete obj;
  std::lock_guard<std::mutex> lck(classobj_ref_count_mutex_);
  --classobj_ref_count_;
}

}  // namespace class_loader
}  // namespace cyber
}  // namespace apollo
#endif  // CYBER_CLASS_LOADER_CLASS_LOADER_H_
