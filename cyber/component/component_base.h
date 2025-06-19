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

#ifndef CYBER_COMPONENT_COMPONENT_BASE_H_
#define CYBER_COMPONENT_COMPONENT_BASE_H_

#include <atomic>
#include <memory>
#include <string>
#include <vector>

#include "gflags/gflags.h"

#include "cyber/proto/component_conf.pb.h"

#include "cyber/class_loader/class_loader.h"
#include "cyber/common/environment.h"
#include "cyber/common/file.h"
#include "cyber/node/node.h"
#include "cyber/scheduler/scheduler.h"

namespace apollo {
namespace cyber {

using apollo::cyber::proto::ComponentConfig;
using apollo::cyber::proto::TimerComponentConfig;

class ComponentBase : public std::enable_shared_from_this<ComponentBase> { // base for all components
 public:
  template <typename M>
  using Reader = cyber::Reader<M>; // reader type alias

  virtual ~ComponentBase() {}

  virtual bool Initialize(const ComponentConfig& config) { return false; } // init with component config
  virtual bool Initialize(const TimerComponentConfig& config) { return false; } // init with timer config
  virtual void Shutdown() { // clean up resources
    if (is_shutdown_.exchange(true)) { // check already shutdown
      return; // ignore repeated calls
    }

    Clear(); // call subclass cleanup
    for (auto& reader : readers_) { // stop each reader
      reader->Shutdown(); // shutdown reader
    }
    scheduler::Instance()->RemoveTask(node_->Name()); // remove task from scheduler
  }

  template <typename T>
  bool GetProtoConfig(T* config) const { // load protobuf config file
    return common::GetProtoFromFile(config_file_path_, config); // parse proto
  }

 protected:
  virtual bool Init() = 0; // subclass initialization
  virtual void Clear() { return; } // subclass cleanup
  const std::string& ConfigFilePath() const { return config_file_path_; } // expose config path

  void LoadConfigFiles(const ComponentConfig& config) { // parse component config paths
    if (!config.config_file_path().empty()) { // check config path
      if (!common::GetFilePathWithEnv(config.config_file_path(),
                                      "APOLLO_CONF_PATH", &config_file_path_)) {
        AERROR << "conf file [" << config.config_file_path() << "] not found!";
        config_file_path_ = config.config_file_path(); // store raw path
      } else {
        AINFO << "use config file: " << config_file_path_; // record actual path
      }
    }

    if (!config.flag_file_path().empty()) { // optional gflags file
      std::string flag_file_path = config.flag_file_path();  // path buffer
      if (!common::GetFilePathWithEnv(config.flag_file_path(),
                                      "APOLLO_FLAG_PATH", &flag_file_path)) {
        AERROR << "flag file [" << config.flag_file_path() << "] not found!"; // error if missing
      } else {
        AINFO << "use flag file: " << flag_file_path; // path resolved
      }
      google::SetCommandLineOption("flagfile", flag_file_path.c_str()); // load flags
    }
  }

  void LoadConfigFiles(const TimerComponentConfig& config) { // similar to above for timer config
    if (!config.config_file_path().empty()) {
      if (!common::GetFilePathWithEnv(config.config_file_path(),
                                      "APOLLO_CONF_PATH", &config_file_path_)) {
        AERROR << "conf file [" << config.config_file_path() << "] not found!";
        config_file_path_ = config.config_file_path();
      } else {
        AINFO << "use config file: " << config_file_path_;
      }
    }

    if (!config.flag_file_path().empty()) {
      std::string flag_file_path = config.flag_file_path();
      if (!common::GetFilePathWithEnv(config.flag_file_path(),
                                      "APOLLO_FLAG_PATH", &flag_file_path)) {
        AERROR << "flag file [" << config.flag_file_path() << "] not found!";
      } else {
        AINFO << "use flag file: " << flag_file_path;
      }
      google::SetCommandLineOption("flagfile", flag_file_path.c_str());
    }
  }

  std::atomic<bool> is_shutdown_ = {false};
  std::shared_ptr<Node> node_ = nullptr;
  std::string config_file_path_ = "";
  std::vector<std::shared_ptr<ReaderBase>> readers_;
};

}  // namespace cyber
}  // namespace apollo

#endif  // CYBER_COMPONENT_COMPONENT_BASE_H_
