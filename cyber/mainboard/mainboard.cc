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

#include <string.h>

#include <list>
#include <string>

#include "cyber/common/global_data.h"
#include "cyber/common/log.h"
#include "cyber/init.h"
#include "cyber/mainboard/module_argument.h"
#include "cyber/mainboard/module_controller.h"
#include "cyber/state.h"

#include "gperftools/profiler.h"
#include "gperftools/heap-profiler.h"
#include "gperftools/malloc_extension.h"

using apollo::cyber::mainboard::ModuleArgument;
using apollo::cyber::mainboard::ModuleController;

int main(int argc, char** argv) {
  // parse the argument
  ModuleArgument module_args;
  module_args.ParseArgument(argc, argv);

  auto dag_list = module_args.GetDAGConfList(); //get the dag conf list
// if the list is empty, return error
  std::string dag_info;
  for (auto&& i = dag_list.begin(); i != dag_list.end(); i++) { // iterate through the dag conf list
    size_t pos = 0;
    for (size_t j = 0; j < (*i).length(); j++) { // find the last '/'
      pos = ((*i)[j] == '/') ? j: pos; // update pos to last '/'
    }
    if (i != dag_list.begin()) dag_info += "_"; // add '_' if not the first element
    // append the substring after the last '/' to dag_info

    if (pos == 0) {
      dag_info += *i; // if no '/' found, use the whole string
    } else {
      dag_info +=
        (pos == (*i).length()-1) ? (*i).substr(pos): (*i).substr(pos+1); // else use the substring after the last '/'
    }
  }

  if (module_args.GetProcessGroup() !=
        apollo::cyber::mainboard::DEFAULT_process_group_) {
    dag_info = module_args.GetProcessGroup(); // if process group is set, use it as dag_info
  }

  // initialize cyber
  apollo::cyber::Init(argv[0], dag_info);

  static bool enable_cpu_profile = module_args.GetEnableCpuprofile(); // check if cpu profile is enabled
  static bool enable_mem_profile = module_args.GetEnableHeapprofile();//  check if memory profile is enabled
  std::signal(SIGTERM, [](int sig){ // handle SIGTERM signal
    apollo::cyber::OnShutdown(sig); // call shutdown handler
    if (enable_cpu_profile) { 
      ProfilerStop(); // stop cpu profiler
    }

    if (enable_mem_profile) {
      HeapProfilerDump("Befor shutdown");// dump memory profile before shutdown
      HeapProfilerStop(); // stop memory profiler
    }
  });

  if (module_args.GetEnableHeapprofile()) { // if memory profiling is enabled
    auto profile_filename = module_args.GetHeapProfileFilename(); 
    HeapProfilerStart(profile_filename.c_str()); // start memory profiler
  }

  // start module
  ModuleController controller(module_args); // create a module controller with the parsed arguments
  if (!controller.Init()) {
    controller.Clear();
    AERROR << "module start error.";
    return -1;
  }

  if (module_args.GetEnableCpuprofile()) {
    auto profile_filename = module_args.GetProfileFilename();
    ProfilerStart(profile_filename.c_str());
  }

  apollo::cyber::WaitForShutdown();

  if (module_args.GetEnableCpuprofile()) {
    ProfilerStop();
  }

  if (module_args.GetEnableHeapprofile()) {
    HeapProfilerDump("Befor shutdown");
    HeapProfilerStop();
  }

  controller.Clear();
  AINFO << "exit mainboard.";

  return 0;
}
