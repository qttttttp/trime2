// SPDX-FileCopyrightText: 2015 - 2024 Rime community
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include <rime_api.h>

// r27.55：native 内存清理（dlsym + API level 守卫）
#include <dlfcn.h>
#include <android/api-level.h>

#include <string>
#include <vector>
#include <array>
#include <map>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cctype>
#include <algorithm>
#include <malloc.h>

#include "jni-utils.h"
#include "objconv.h"
#include "proto.h"
#include "session.h"

#define MAX_BUFFER_LENGTH 2048

extern void rime_require_module_lua();
extern void rime_require_module_octagram();
extern void rime_require_module_predict();
// librime is compiled as a static library, we have to link modules explicitly
static void declare_librime_module_dependencies() {
  rime_require_module_lua();
  rime_require_module_octagram();
  rime_require_module_predict();
}

class Rime {
 public:
  Rime() : rime(rime_get_api()) {}
  Rime(Rime const &) = delete;
  void operator=(Rime const &) = delete;

  static Rime &Instance() {
    static Rime instance;
    return instance;
  }

  void startup(bool fullCheck,
               const RimeNotificationHandler &notificationHandler) {
    if (!rime) return;
    const char *userDir = getenv("RIME_USER_DATA_DIR");
    const char *sharedDir = getenv("RIME_SHARED_DATA_DIR");
    const char *versionName = getenv("RIME_DISTRIBUTION_VERSION");

    RIME_STRUCT(RimeTraits, trime_traits)
    trime_traits.shared_data_dir = sharedDir;
    trime_traits.user_data_dir = userDir;
    trime_traits.log_dir = "";  // set empty log_dir to log to logcat only
    trime_traits.app_name = "rime.trime";
    trime_traits.distribution_name = "Trime";
    trime_traits.distribution_code_name = "trime";
    trime_traits.distribution_version = versionName;

    rime->setup(&trime_traits);
    rime->initialize(&trime_traits);
    rime->set_notification_handler(notificationHandler, GlobalRef->jvm);
    rime->start_maintenance(fullCheck);
  }

  bool deploySchema(std::string_view schemaFile) {
    return rime->deploy_schema(schemaFile.data());
  }

  bool deployConfigFile(std::string_view configFile,
                        std::string_view versionKey) {
    return rime->deploy_config_file(configFile.data(), versionKey.data());
  }

  bool processKey(int keycode, int mask) {
    return rime->process_key(session(), keycode, mask);
  }

  bool simulateKeySequence(const std::string &sequence) {
    return rime->simulate_key_sequence(session(), sequence.data());
  }

  bool commitComposition() { return rime->commit_composition(session()); }

  void clearComposition() { rime->clear_composition(session()); }

  void commitProto(uintptr_t builder) { rime_commit_proto(session(), builder); }

  void contextProto(uintptr_t builder) {
    rime_context_proto(session(), builder);
  }

  void statusProto(uintptr_t builder) { rime_status_proto(session(), builder); }

  void setOption(std::string_view key, bool value) {
    rime->set_option(session(), key.data(), value);
  }

  bool getOption(std::string_view key) {
    return rime->get_option(session(), key.data());
  }

  // 字符串键值对（property）：Java 层 ↔ librime ↔ librime-lua 的数据通道。
  // Lua 侧用 context:get_property(key) / context:set_property(key, value) 读写，
  // 与这里操作的是同一份存储（Context::properties_），可用来传任意字符串数据。
  void setProperty(std::string_view key, std::string_view value) {
    rime->set_property(session(), key.data(), value.data());
  }

  std::string getProperty(std::string_view key) {
    char result[MAX_BUFFER_LENGTH];
    return rime->get_property(session(), key.data(), result, MAX_BUFFER_LENGTH)
               ? result
               : "";
  }

  std::string currentSchemaId() {
    char result[MAX_BUFFER_LENGTH];
    return rime->get_current_schema(session(), result, MAX_BUFFER_LENGTH)
               ? result
               : "";
  }

  std::vector<SchemaItem> schemaList() {
    std::vector<SchemaItem> result;
    RimeSchemaList list{};
    if (rime->get_schema_list(&list)) {
      result = SchemaItem::fromCList(list);
      rime->free_schema_list(&list);
    }
    return std::move(result);
  }

  bool selectSchema(std::string_view schemaId) {
    return rime->select_schema(session(), schemaId.data());
  }

  std::string rawInput() {
    auto cStr = rime->get_input(session());
    return cStr ? cStr : "";
  }

  size_t caretPosition() { return rime->get_caret_pos(session()); }

  void setCaretPosition(size_t caretPos) {
    rime->set_caret_pos(session(), caretPos);
  }

  bool selectCandidateOnCurrentPage(size_t index) {
    return rime->select_candidate_on_current_page(session(), index);
  }

  bool deleteCandidateOnCurrentPage(size_t index) {
    return rime->delete_candidate_on_current_page(session(), index);
  }

  bool selectCandidate(size_t index) {
    return rime->select_candidate(session(), index);
  }

  bool forgetCandidate(size_t index) {
    return rime->delete_candidate(session(), index);
  }

  bool changePage(bool backward) {
    return rime->change_page(session(), backward);
  }

  bool highlightCandidate(size_t index) {
    return rime->highlight_candidate(session(), index);
  }

  size_t getHighlightCandidate() {
    return rime_get_highlighted_candidate_index(session());
  }

  std::vector<CandidateItem> getCandidates(int startIndex, int limit) {
    std::vector<CandidateItem> result;
    result.reserve(limit);
    RimeCandidateListIterator iter{};
    if (rime->candidate_list_from_index(session(), &iter, startIndex)) {
      int count = 0;
      while (rime->candidate_list_next(&iter)) {
        if (count >= limit) break;
        const CandidateItem item(iter.candidate);
        result.emplace_back(item);
        ++count;
      }
      rime->candidate_list_end(&iter);
    }
    return std::move(result);
  }

  void exit() {
    session_.reset();
    rime->finalize();
  }

  bool sync() {
    session_.reset();
    return rime->sync_user_data();
  }

  // r27.63：诊断专用。先读出当前 schema id，再真正销毁会话（destroy_session），
  // 释放会话/引擎/翻译器/词典持有的活内存。返回销毁前的 schema id 供随后恢复。
  // 注意：currentSchemaId() 内部会确保 session 存在，故必须在 reset 之前调用。
  std::string releaseSessionForDiag() {
    std::string schema = currentSchemaId();
    session_.reset();
    return schema;
  }

  // r27.63：诊断专用。重建会话并切回原 schema，做到用户无感知恢复。
  // session() 会在 session_ 为空时重新 create_session；随后 select_schema。
  bool restoreSessionForDiag(std::string_view schemaId) {
    if (!session()) return false;
    if (schemaId.empty()) return true;
    return selectSchema(schemaId);
  }

 private:
  RimeApi *rime;
  std::shared_ptr<SessionHolder> session_;

  RimeSessionId session(bool requestNewSession = true) {
    if (!session_ && requestNewSession) {
      try {
        auto newSession = std::make_shared<SessionHolder>();
        session_ = newSession;
      } catch (...) {
        session_ = nullptr;
      }
    }
    if (!session_) {
      return 0;
    }
    return session_->id();
  }
};

GlobalRefSingleton *GlobalRef;

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *jvm, void *reserved) {
  GlobalRef = new GlobalRefSingleton(jvm);
  declare_librime_module_dependencies();
  return JNI_VERSION_1_6;
}

extern "C" JNIEXPORT void JNICALL Java_com_osfans_trime_core_Rime_startupRime(
    JNIEnv *env, jclass clazz, jstring shared_dir, jstring user_dir,
    jstring version_name, jboolean full_check) {
  // for rime shared data dir
  setenv("RIME_SHARED_DATA_DIR", CString(env, shared_dir), 1);
  // for rime user data dir
  setenv("RIME_USER_DATA_DIR", CString(env, user_dir), 1);
  setenv("RIME_DISTRIBUTION_VERSION", CString(env, version_name), 1);

  auto notificationHandler = [](void *context_object, RimeSessionId session_id,
                                const char *message_type,
                                const char *message_value) {
    auto env = GlobalRef->AttachEnv();
    int type = 0;  // unknown
    if (strcmp(message_type, "schema") == 0) {
      type = 1;
    } else if (strcmp(message_type, "option") == 0) {
      type = 2;
    } else if (strcmp(message_type, "deploy") == 0) {
      type = 3;
    }
    auto vararg = JRef<jobjectArray>(
        env, env->NewObjectArray(1, GlobalRef->Object, nullptr));
    env->SetObjectArrayElement(vararg, 0, JString(env, message_value));
    env->CallStaticVoidMethod(GlobalRef->Rime, GlobalRef->HandleRimeMessage,
                              type, *vararg);
  };

  Rime::Instance().startup(full_check, notificationHandler);
}

extern "C" JNIEXPORT void JNICALL
Java_com_osfans_trime_core_Rime_exitRime(JNIEnv *env, jclass /* thiz */) {
  Rime::Instance().exit();
}

// deployment
extern "C" JNIEXPORT jboolean JNICALL
Java_com_osfans_trime_core_Rime_deployRimeSchemaFile(JNIEnv *env,
                                                     jclass /* thiz */,
                                                     jstring schema_file) {
  return Rime::Instance().deploySchema(*CString(env, schema_file));
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_osfans_trime_core_Rime_deployRimeConfigFile(JNIEnv *env,
                                                     jclass /* thiz */,
                                                     jstring file_name,
                                                     jstring version_key) {
  return Rime::Instance().deployConfigFile(*CString(env, file_name),
                                           *CString(env, version_key));
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_osfans_trime_core_Rime_syncRimeUserData(JNIEnv *env,
                                                 jclass /* thiz */) {
  return Rime::Instance().sync();
}

// input
extern "C" JNIEXPORT jboolean JNICALL
Java_com_osfans_trime_core_Rime_processRimeKey(JNIEnv *env, jclass /* thiz */,
                                               jint keycode, jint mask) {
  return Rime::Instance().processKey(keycode, mask);
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_osfans_trime_core_Rime_commitRimeComposition(JNIEnv *env,
                                                      jclass /* thiz */) {
  return Rime::Instance().commitComposition();
}

extern "C" JNIEXPORT void JNICALL
Java_com_osfans_trime_core_Rime_clearRimeComposition(JNIEnv *env,
                                                     jclass /* thiz */) {
  Rime::Instance().clearComposition();
}

// output
extern "C" JNIEXPORT jobject JNICALL
Java_com_osfans_trime_core_Rime_getRimeCommit(JNIEnv *env, jclass /* thiz */) {
  rime::proto::Commit commit;
  Rime::Instance().commitProto(reinterpret_cast<uintptr_t>(&commit));
  return rimeProtoCommitToJObject(env, commit);
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_osfans_trime_core_Rime_getRimeContext(JNIEnv *env, jclass /* thiz */) {
  rime::proto::Context context;
  Rime::Instance().contextProto(reinterpret_cast<uintptr_t>(&context));
  return rimeProtoContextToJObject(env, context);
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_osfans_trime_core_Rime_getRimeStatus(JNIEnv *env, jclass /* thiz */) {
  rime::proto::Status status;
  Rime::Instance().statusProto(reinterpret_cast<uintptr_t>(&status));
  return rimeProtoStatusToJObject(env, status);
}

// runtime options
extern "C" JNIEXPORT void JNICALL Java_com_osfans_trime_core_Rime_setRimeOption(
    JNIEnv *env, jclass /* thiz */, jstring option, jboolean value) {
  Rime::Instance().setOption(*CString(env, option), value);
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_osfans_trime_core_Rime_getRimeOption(JNIEnv *env, jclass /* thiz */,
                                              jstring option) {
  return Rime::Instance().getOption(*CString(env, option));
}

// runtime properties：Java ↔ librime ↔ librime-lua 传字符串数据
extern "C" JNIEXPORT void JNICALL Java_com_osfans_trime_core_Rime_setRimeProperty(
    JNIEnv *env, jclass /* thiz */, jstring prop, jstring value) {
  const char *key = *CString(env, prop);
  const char *val = *CString(env, value);
  Rime::Instance().setProperty(key, val);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_osfans_trime_core_Rime_getRimeProperty(JNIEnv *env, jclass /* thiz */,
                                                jstring prop) {
  std::string value = Rime::Instance().getProperty(*CString(env, prop));
  return env->NewStringUTF(value.c_str());
}

// r27.55：归还 native 层已 free 但未还给内核的空闲页。
// Android 的 malloc 分配器默认保留空闲页以加速下次分配，长时间输入后
// 累积显著，表现为 native PSS 一路涨。M_PURGE 强制立即归还，不杀进程、
// 不影响 Java 对象，执行仅几十毫秒。
extern "C" JNIEXPORT void JNICALL
Java_com_osfans_trime_core_Rime_purgeNativeMemory(JNIEnv *env,
                                                  jclass /* thiz */) {
#ifdef __ANDROID__
  // mallopt 符号仅 API 26+ 存在，M_PURGE 仅 API 28+ 有效。项目 minSdk=21，
  // 若直接调用会让低版本设备加载 so 时因缺符号失败，故用 dlsym 运行时解析。
  if (android_get_device_api_level() < 28) return;
  using MalloptFn = int (*)(int, int);
  static MalloptFn s_mallopt = nullptr;
  static bool s_resolved = false;
  if (!s_resolved) {
    s_mallopt = reinterpret_cast<MalloptFn>(dlsym(RTLD_DEFAULT, "mallopt"));
    s_resolved = true;
  }
  if (s_mallopt) s_mallopt(-101, 0);  // M_PURGE
#endif
}

//============================================================
// r27.66：只读内存映射诊断。不改任何状态、不释放任何内存，
// 仅采集 /proc/self/smaps 按文件聚合 PSS + malloc 分配器统计，
// 用于定位"anonymous 活内存"与"mmap 词库文件"各占多少。
//============================================================
namespace memdiag {

struct Agg {
  long pss_kb = 0;
  int  maps = 0;
  std::string top_path;
  long top_kb = 0;
};

// 把 smaps 的一个 pathname 归类。词库文件通常是 .table.bin/.prism.bin，
// 用户词典是 leveldb 的 .ldb/CURRENT/MANIFEST/LOG，都在 Documents/rime 下。
static const char* classify(const std::string& path) {
  if (path.empty()) return "anonymous(堆/栈/匿名mmap)";
  if (path.find("userdb") != std::string::npos ||
      path.find("leveldb") != std::string::npos ||
      path.find("user_dict") != std::string::npos ||
      path.size() >= 4 && path.compare(path.size() - 4, 4, ".ldb") == 0 ||
      path.find("CURRENT") != std::string::npos ||
      path.find("MANIFEST") != std::string::npos)
    return "用户词典(leveldb)";
  if (path.find(".table.bin") != std::string::npos ||
      path.find(".prism.bin") != std::string::npos ||
      path.find("rime") != std::string::npos && path.find(".bin") != std::string::npos)
    return "静态词库(table/prism)";
  if (path.compare(0, 6, "[anon:") == 0) return "ART/[anon]";
  if (path == "[heap]") return "[heap]";
  if (path.find(".so") != std::string::npos) return "so库";
  if (path.find(".dex") != std::string::npos ||
      path.find(".art") != std::string::npos ||
      path.find(".oat") != std::string::npos ||
      path.find(".apk") != std::string::npos)
    return "dex/art/apk";
  if (path[0] == '/') return "其它文件映射";
  return "其它";
}

static std::string formatMb(long kb) {
  char buf[64];
  snprintf(buf, sizeof(buf), "%.1f", kb / 1024.0);
  return buf;
}

// 读 /proc/self/smaps_rollup 的若干字段
static void readRollup(std::array<long, 6>& out) {
  out = {0, 0, 0, 0, 0, 0};  // Pss, Pss_Anon, Pss_File, Pss_Shmem, Rss, Private_Dirty
  FILE* f = fopen("/proc/self/smaps_rollup", "r");
  if (!f) return;
  char line[256];
  const char* keys[6] = {"Pss:", "Pss_Anon:", "Pss_File:", "Pss_Shmem:", "Rss:", "Private_Dirty:"};
  while (fgets(line, sizeof(line), f)) {
    for (int i = 0; i < 6; ++i) {
      if (strncmp(line, keys[i], strlen(keys[i])) == 0) {
        out[i] = atol(line + strlen(keys[i]));
        break;
      }
    }
  }
  fclose(f);
}

// 读 /proc/self/smaps，按分类聚合 PSS，并记录每类最大单映射
static void readSmaps(std::map<std::string, Agg>& agg) {
  FILE* f = fopen("/proc/self/smaps", "r");
  if (!f) return;
  char line[512];
  std::string cur_path;
  long cur_pss = 0;
  auto flush = [&]() {
    if (cur_pss <= 0) return;
    const char* cat = classify(cur_path);
    Agg& a = agg[cat];
    a.pss_kb += cur_pss;
    a.maps += 1;
    if (cur_pss > a.top_kb) { a.top_kb = cur_pss; a.top_path = cur_path.empty() ? "(anonymous)" : cur_path; }
  };
  while (fgets(line, sizeof(line), f)) {
    // 映射头格式: "7f...-7f... r--p 00000 ... /path/to/file"
    if (strchr(line, '-') && strstr(line, " ") && isxdigit((unsigned char)line[0])) {
      // 只在行首是十六进制地址且含 perms 时视为头行
      if (strspn(line, "0123456789abcdefABCDEF") > 4 && line[strspn(line, "0123456789abcdefABCDEF")] == '-') {
        flush();
        cur_path.clear();
        cur_pss = 0;
        // 路径是第 6 个字段之后（addr perms offset dev inode path）
        char* p = line;
        for (int field = 0; field < 5; ++field) {
          while (*p && *p != ' ') ++p;
          while (*p == ' ') ++p;
        }
        if (*p && *p != '\n') {
          cur_path = p;
          while (!cur_path.empty() && (cur_path.back() == '\n' || cur_path.back() == ' ')) cur_path.pop_back();
        }
        continue;
      }
    }
    if (strncmp(line, "Pss:", 4) == 0) cur_pss += atol(line + 4);
  }
  flush();
  fclose(f);
}

struct MallocSnap {
  bool ok = false;
  size_t arena = 0, uordblks = 0, fordblks = 0, keepcost = 0, hblkhd = 0;
};

// mallinfo2 仅较新 NDK 有；用 dlsym 兼容，失败回退 mallinfo（字段窄但可读）
static MallocSnap readMalloc() {
  MallocSnap s;
#if defined(__ANDROID__) && defined(MALLOC_MALLINFO2_H)
  using Fn = struct mallinfo2 (*)();
  static Fn fn = nullptr;
  static bool resolved = false;
  if (!resolved) {
    fn = reinterpret_cast<Fn>(dlsym(RTLD_DEFAULT, "mallinfo2"));
    resolved = true;
  }
  if (fn) {
    auto m = fn();
    s.ok = true;
    s.arena = m.arena; s.uordblks = m.uordblks; s.fordblks = m.fordblks;
    s.keepcost = m.keepcost; s.hblkhd = m.hblkhd;
    return s;
  }
#endif
  struct mallinfo m = mallinfo();
  s.ok = true;
  s.arena = (size_t)m.arena; s.uordblks = (size_t)m.uordblks;
  s.fordblks = (size_t)m.fordblks; s.keepcost = (size_t)m.keepcost;
  s.hblkhd = (size_t)m.hblkhd;
  return s;
}

static std::string buildReport() {
  std::array<long, 6> r{};
  readRollup(r);
  std::map<std::string, Agg> agg;
  readSmaps(agg);
  MallocSnap mi = readMalloc();

  char buf[512];
  std::string out;
  out.reserve(4096);
  out += "========== native 内存映射诊断(r27.66) ==========\n";
  snprintf(buf, sizeof(buf), "SDK=%d\n", android_get_device_api_level());
  out += buf;
  out += "\n-- smaps_rollup (MB) --\n";
  snprintf(buf, sizeof(buf),
           "Pss=%.1f  Pss_Anon=%.1f  Pss_File=%.1f  Pss_Shmem=%.1f  Rss=%.1f  Private_Dirty=%.1f\n",
           r[0]/1024.0, r[1]/1024.0, r[2]/1024.0, r[3]/1024.0, r[4]/1024.0, r[5]/1024.0);
  out += buf;
  out += "Pss_Anon = 匿名活内存(堆/栈/分配器/librime对象)  Pss_File = 文件映射(词库mmap/dex/so)\n";

  out += "\n-- 按文件类型聚合 PSS (MB / 映射数) --\n";
  // 按 pss 降序
  std::vector<std::pair<std::string, Agg>> vec(agg.begin(), agg.end());
  std::sort(vec.begin(), vec.end(), [](const std::pair<std::string, Agg>& a,
                                       const std::pair<std::string, Agg>& b) {
    return a.second.pss_kb > b.second.pss_kb;
  });
  for (const auto& kv : vec) {
    const Agg& a = kv.second;
    snprintf(buf, sizeof(buf), "%-30s %8s / %4d  最大单映射: %s MB\n",
             kv.first.c_str(), formatMb(a.pss_kb).c_str(), a.maps, formatMb(a.top_kb).c_str());
    out += buf;
    snprintf(buf, sizeof(buf), "    └ %s\n", a.top_path.c_str());
    out += buf;
  }

  out += "\n-- malloc 分配器 (MB) --\n";
  if (mi.ok) {
    snprintf(buf, sizeof(buf),
             "arena=%.1f  uordblks(已分配)=%.1f  fordblks(空闲)=%.1f  keepcost(可归还)=%.1f  hblkhd(mmap)=%.1f\n",
             mi.arena/1048576.0, mi.uordblks/1048576.0, mi.fordblks/1048576.0,
             mi.keepcost/1048576.0, mi.hblkhd/1048576.0);
    out += buf;
  } else {
    out += "mallinfo 不可用\n";
  }
  return out;
}

}  // namespace memdiag

// r27.66：诊断专用——只读采集内存映射分布，返回格式化报告字符串。
// 不修改任何状态、不释放任何内存，可安全重复调用。
extern "C" JNIEXPORT jstring JNICALL
Java_com_osfans_trime_core_Rime_dumpMemoryAnalysisForDiag(JNIEnv *env,
                                                          jclass /* thiz */) {
  std::string report = memdiag::buildReport();
  return env->NewStringUTF(report.c_str());
}

// r27.63：诊断专用——真正销毁 librime session，返回销毁前的 schema id。
extern "C" JNIEXPORT jstring JNICALL
Java_com_osfans_trime_core_Rime_releaseRimeSessionForDiag(JNIEnv *env,
                                                          jclass /* thiz */) {
  std::string schema = Rime::Instance().releaseSessionForDiag();
  return env->NewStringUTF(schema.c_str());
}

// r27.63：诊断专用——重建 session 并切回原 schema，用户无感知恢复。
extern "C" JNIEXPORT jboolean JNICALL
Java_com_osfans_trime_core_Rime_restoreRimeSessionForDiag(
    JNIEnv *env, jclass /* thiz */, jstring schema_id) {
  bool ok = Rime::Instance().restoreSessionForDiag(*CString(env, schema_id));
  return ok ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jobjectArray JNICALL
Java_com_osfans_trime_core_Rime_getRimeSchemaList(JNIEnv *env,
                                                  jclass /* thiz */) {
  return rimeSchemaListToJObjectArray(env, Rime::Instance().schemaList());
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_osfans_trime_core_Rime_getCurrentRimeSchema(JNIEnv *env,
                                                     jclass /* thiz */) {
  return env->NewStringUTF(Rime::Instance().currentSchemaId().c_str());
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_osfans_trime_core_Rime_selectRimeSchema(JNIEnv *env, jclass /* thiz */,
                                                 jstring schema_id) {
  return Rime::Instance().selectSchema(*CString(env, schema_id));
}

// testing
extern "C" JNIEXPORT jboolean JNICALL
Java_com_osfans_trime_core_Rime_simulateRimeKeySequence(JNIEnv *env,
                                                        jclass /* thiz */,
                                                        jstring key_sequence) {
  return Rime::Instance().simulateKeySequence(CString(env, key_sequence));
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_osfans_trime_core_Rime_getRimeRawInput(JNIEnv *env,
                                                jclass /* thiz */) {
  return env->NewStringUTF(Rime::Instance().rawInput().data());
}

extern "C" JNIEXPORT jint JNICALL
Java_com_osfans_trime_core_Rime_getRimeCaretPos(JNIEnv *env,
                                                jclass /* thiz */) {
  return static_cast<jint>(Rime::Instance().caretPosition());
}

extern "C" JNIEXPORT void JNICALL
Java_com_osfans_trime_core_Rime_setRimeCaretPos(JNIEnv *env, jclass /* thiz */,
                                                jint caret_pos) {
  Rime::Instance().setCaretPosition(caret_pos);
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_osfans_trime_core_Rime_selectRimeCandidateOnCurrentPage(
    JNIEnv *env, jclass /* thiz */, jint index) {
  return Rime::Instance().selectCandidateOnCurrentPage(index);
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_osfans_trime_core_Rime_deleteRimeCandidateOnCurrentPage(
    JNIEnv *env, jclass /* thiz */, jint index) {
  return Rime::Instance().deleteCandidateOnCurrentPage(index);
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_osfans_trime_core_Rime_selectRimeCandidate(JNIEnv *env,
                                                    jclass /* thiz */,
                                                    jint index) {
  return Rime::Instance().selectCandidate(index);
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_osfans_trime_core_Rime_forgetRimeCandidate(JNIEnv *env,
                                                    jclass /* thiz */,
                                                    jint index) {
  return Rime::Instance().forgetCandidate(index);
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_osfans_trime_core_Rime_changeRimeCandidatePage(JNIEnv *env,
                                                        jclass clazz,
                                                        jboolean backward) {
  return Rime::Instance().changePage(backward);
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_osfans_trime_core_Rime_highlightRimeCandidate(JNIEnv *env,
                                                    jclass /* thiz */,
                                                    jint index) {
  return Rime::Instance().highlightCandidate(index);
}

extern "C" JNIEXPORT jint JNICALL
Java_com_osfans_trime_core_Rime_getHighlightRimeCandidate(JNIEnv *env,
                                                       jclass /* thiz */) {
  return Rime::Instance().getHighlightCandidate();;
}

extern "C" JNIEXPORT jobjectArray JNICALL
Java_com_osfans_trime_core_Rime_getRimeCandidates(JNIEnv *env, jclass clazz,
                                                  jint start_index,
                                                  jint limit) {
  return rimeCandidateListToJObjectArray(
      env, Rime::Instance().getCandidates(start_index, limit));
}
