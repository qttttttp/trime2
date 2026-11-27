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
#include <ctime>
#include <atomic>
#include <cstdint>

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

  // r27.83 / 25号：安全回收前置判断。仅当当前编码为空（未在输入）时允许
  // 销毁并重建 session，避免丢失用户正在输入的编码。
  bool canRecycleSession() {
    std::string input = rawInput();
    return input.empty();
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

// r27.87：增长探针前向声明（包装点在文件前部，实现体在 memdiag 之后）。
// 必须先声明，否则 processKey/commitComposition/getContext 等包装点认不出 growprobe。
namespace growprobe {
extern bool enabled;
long long curKb();
void record(int op, long long before_kb);
}

// input
extern "C" JNIEXPORT jboolean JNICALL
Java_com_osfans_trime_core_Rime_processRimeKey(JNIEnv *env, jclass /* thiz */,
                                               jint keycode, jint mask) {
  long long _b = growprobe::enabled ? growprobe::curKb() : 0;
  bool _r = Rime::Instance().processKey(keycode, mask);
  growprobe::record(0, _b);  // processKey
  return _r;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_osfans_trime_core_Rime_commitRimeComposition(JNIEnv *env,
                                                      jclass /* thiz */) {
  long long _b = growprobe::enabled ? growprobe::curKb() : 0;
  bool _r = Rime::Instance().commitComposition();
  growprobe::record(3, _b);  // commitComposition
  return _r;
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
  long long _b = growprobe::enabled ? growprobe::curKb() : 0;
  rime::proto::Context context;
  Rime::Instance().contextProto(reinterpret_cast<uintptr_t>(&context));
  jobject _r = rimeProtoContextToJObject(env, context);
  growprobe::record(2, _b);  // getContext
  return _r;
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
// r27.69：只读内存映射诊断。不改任何状态、不释放任何内存，
// 仅采集 /proc/self/smaps 按文件聚合 PSS + malloc 分配器统计，
// 用于定位"anonymous 活内存"与"mmap 词库文件"各占多少。
//============================================================
//============================================================
// r27.88 / 26号诊断补丁：native 分配栈归因（默认关闭）。
// 目标：定位"增长发生在 5 个入口之外"时，究竟是哪段 native 代码在持续 new。
//
// 设计要点（把风险压到最低）：
//  1. 只重载全局 operator new / new[]（内部用 malloc），不重载任何 delete。
//     释放仍走系统默认 operator delete（libc++ 内部即 free）。malloc↔free
//     天然配对，不存在"new 我方 / delete 系统"的配对崩溃风险。
//  2. 每次 new 用 __builtin_return_address(0) 取直接调用者 PC，按 PC 聚合
//     "累计分配字节 / 次数"。PC 是代码地址，dump 时用 dladdr 解析成
//     "so 名 + 偏移"，配合 addr2line 可定位到源码行。
//  3. hook 内只做原子加和固定大小静态哈希表的线性探测，绝不申请内存、
//     绝不调用 dladdr/snprintf/std::string（否则递归）。符号解析只在 dump 做。
//  4. 默认关闭；关闭时 operator new 仅多一次原子读 + malloc，无其它开销。
//  5. 只统计 >= 阈值的分配（默认 256B），过滤海量微小临时分配，降低表压力。
//
// 局限：累计分配量高 != 泄漏（可能是高频临时分配），需结合多次 dump 的
//       uordblks 净增趋势判断；且需未 strip 的 so 才能符号化到源码行。
//============================================================
namespace allocprobe {

constexpr int kSlots = 4096;          // 必须是 2 的幂
struct Slot {
  std::atomic<void*> pc{nullptr};     // nullptr = 空槽；否则为分配点返回地址
  std::atomic<size_t> bytes{0};
  std::atomic<long> calls{0};
};
static Slot g_slots[kSlots];

static std::atomic<bool> g_enabled{false};
static std::atomic<size_t> g_threshold{256};     // 只统计 >= 该字节数的分配
static std::atomic<size_t> g_totalBytes{0};
static std::atomic<long> g_totalCalls{0};
static std::atomic<long> g_skipped{0};           // 小分配/表满被跳过的次数

// 64 位混合哈希（MurmurHash3 finalizer 风格），把 PC 打散到各槽
static inline size_t hashPc(void* p) {
  uintptr_t x = (uintptr_t)p >> 2;               // 指令地址 4 字节对齐
  x ^= x >> 16;
  x *= 0x7feb352dULL;
  x ^= x >> 15;
  x *= 0x846ca68bULL;
  x ^= x >> 16;
  return (size_t)x;
}

// 在 operator new 内调用：pc 已由调用方用 __builtin_return_address(0) 取得。
// 无锁：用原子 CAS 抢占空槽，再用原子加累计，全程不分配。
static inline void account(void* pc, size_t n) {
  if (!g_enabled.load(std::memory_order_relaxed)) return;
  if (n < g_threshold.load(std::memory_order_relaxed)) {
    g_skipped.fetch_add(1, std::memory_order_relaxed);
    return;
  }
  size_t idx = hashPc(pc) & (kSlots - 1);
  for (int probe = 0; probe < kSlots; ++probe) {
    Slot& s = g_slots[(idx + probe) & (kSlots - 1)];
    void* cur = s.pc.load(std::memory_order_relaxed);
    if (cur == pc) {
      s.bytes.fetch_add(n, std::memory_order_relaxed);
      s.calls.fetch_add(1, std::memory_order_relaxed);
      break;
    }
    if (cur == nullptr) {
      void* expected = nullptr;
      if (s.pc.compare_exchange_strong(expected, pc, std::memory_order_relaxed)) {
        s.bytes.fetch_add(n, std::memory_order_relaxed);
        s.calls.fetch_add(1, std::memory_order_relaxed);
        break;
      }
      // CAS 失败：别的线程刚占了此槽，继续探测
    }
  }
  g_totalBytes.fetch_add(n, std::memory_order_relaxed);
  g_totalCalls.fetch_add(1, std::memory_order_relaxed);
}

static void enable(bool on, int thresholdBytes) {
  if (!on) {
    g_enabled.store(false, std::memory_order_release);
    return;
  }
  for (int i = 0; i < kSlots; ++i) {
    g_slots[i].pc.store(nullptr, std::memory_order_relaxed);
    g_slots[i].bytes.store(0, std::memory_order_relaxed);
    g_slots[i].calls.store(0, std::memory_order_relaxed);
  }
  g_totalBytes.store(0, std::memory_order_relaxed);
  g_totalCalls.store(0, std::memory_order_relaxed);
  g_skipped.store(0, std::memory_order_relaxed);
  if (thresholdBytes > 0) {
    g_threshold.store((size_t)thresholdBytes, std::memory_order_relaxed);
  }
  g_enabled.store(true, std::memory_order_release);
}

struct Row {
  size_t bytes;
  long calls;
  void* pc;
};

// dump 阶段调用：此处允许分配（std::string/vector）与 dladdr 符号解析。
// 注意：先把 g_enabled 关掉，避免报告自身的分配污染统计（调用方负责恢复）。
static std::string report() {
  std::string out;
  char buf[320];
  out.reserve(16384);
  out += "========== native 分配栈归因 r27.88 ==========\n";
  snprintf(buf, sizeof(buf), "状态=%s  阈值>=%zuB  累计=%zuMB/%ld次  跳过=%ld\n",
           g_enabled.load(std::memory_order_relaxed) ? "开启" : "关闭",
           g_threshold.load(std::memory_order_relaxed),
           (size_t)(g_totalBytes.load(std::memory_order_relaxed) / 1048576),
           g_totalCalls.load(std::memory_order_relaxed),
           g_skipped.load(std::memory_order_relaxed));
  out += buf;

  std::vector<Row> rows;
  rows.reserve(kSlots);
  for (int i = 0; i < kSlots; ++i) {
    void* pc = g_slots[i].pc.load(std::memory_order_relaxed);
    size_t b = g_slots[i].bytes.load(std::memory_order_relaxed);
    if (pc != nullptr && b > 0) {
      rows.push_back({b, g_slots[i].calls.load(std::memory_order_relaxed), pc});
    }
  }
  std::sort(rows.begin(), rows.end(),
            [](const Row& a, const Row& b) { return a.bytes > b.bytes; });

  out += "\n-- Top 分配点 (累计MB / 次数 / 库+偏移) --\n";
  const int TOP = 30;
  for (int i = 0; i < (int)rows.size() && i < TOP; ++i) {
    Dl_info info;
    const char* lib = "?";
    unsigned long off = 0;
    if (dladdr(rows[i].pc, &info) != 0 && info.dli_fname != nullptr) {
      const char* slash = strrchr(info.dli_fname, '/');
      lib = slash != nullptr ? slash + 1 : info.dli_fname;
      off = (unsigned long)((char*)rows[i].pc - (char*)info.dli_fbase);
    }
    snprintf(buf, sizeof(buf), "  %2d  %7zuMB %7ld次  %s+0x%lx\n",
             i + 1, (size_t)(rows[i].bytes / 1048576), rows[i].calls, lib, off);
    out += buf;
  }
  out += "\n说明: 累计高=该路径分配猛；结合多次 dump 的 uordblks 净增判断是否泄漏。\n";
  out += "符号化: addr2line -Cfipe <未strip的so> 0x<偏移> 定位源码行。\n";
  return out;
}

}  // namespace allocprobe

// 全局 operator new：仅此两个重载，delete 全部用系统默认（free），配对安全。
void* operator new(std::size_t n) {
  void* p = std::malloc(n ? n : 1);
  if (!p) throw std::bad_alloc();
  allocprobe::account(__builtin_return_address(0), n);
  return p;
}
void* operator new[](std::size_t n) { return ::operator new(n); }

//---- allocprobe 分配栈归因结束 ----

namespace memdiag {

struct Agg {
  long pss_kb = 0;
  long clean_kb = 0;   // r27.69：Private_Clean，可回收的文件映射页
  long dirty_kb = 0;   // r27.69：Private_Dirty，真占用的脏页
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

// 读 /proc/self/smaps，按分类聚合 PSS / Private_Clean / Private_Dirty，并记录每类最大单映射
static void readSmaps(std::map<std::string, Agg>& agg) {
  FILE* f = fopen("/proc/self/smaps", "r");
  if (!f) return;
  char line[512];
  std::string cur_path;
  long cur_pss = 0, cur_clean = 0, cur_dirty = 0;
  auto flush = [&]() {
    if (cur_pss <= 0 && cur_dirty <= 0) return;
    const char* cat = classify(cur_path);
    Agg& a = agg[cat];
    a.pss_kb += cur_pss;
    a.clean_kb += cur_clean;
    a.dirty_kb += cur_dirty;
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
        cur_pss = 0; cur_clean = 0; cur_dirty = 0;
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
    else if (strncmp(line, "Private_Clean:", 14) == 0) cur_clean += atol(line + 14);
    else if (strncmp(line, "Private_Dirty:", 14) == 0) cur_dirty += atol(line + 14);
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
  out += "========== native 内存映射诊断(r27.69) ==========\n";
  snprintf(buf, sizeof(buf), "SDK=%d\n", android_get_device_api_level());
  out += buf;
  out += "\n-- smaps_rollup (MB) --\n";
  snprintf(buf, sizeof(buf),
           "Pss=%.1f  Pss_Anon=%.1f  Pss_File=%.1f  Pss_Shmem=%.1f  Rss=%.1f  Private_Dirty=%.1f\n",
           r[0]/1024.0, r[1]/1024.0, r[2]/1024.0, r[3]/1024.0, r[4]/1024.0, r[5]/1024.0);
  out += buf;
  out += "Pss_Anon = 匿名活内存(堆/栈/分配器/librime对象)  Pss_File = 文件映射(词库mmap/dex/so)\n";
  out += "Clean = Private_Clean(可回收文件页)  Dirty = Private_Dirty(真占用脏页)\n";

  out += "\n-- 按文件类型聚合 PSS/Clean/Dirty (MB / 映射数) --\n";
  // 按 pss 降序
  std::vector<std::pair<std::string, Agg>> vec(agg.begin(), agg.end());
  std::sort(vec.begin(), vec.end(), [](const std::pair<std::string, Agg>& a,
                                       const std::pair<std::string, Agg>& b) {
    return a.second.pss_kb > b.second.pss_kb;
  });
  for (const auto& kv : vec) {
    const Agg& a = kv.second;
    snprintf(buf, sizeof(buf), "%-30s PSS=%7s Clean=%7s Dirty=%7s / %4d 最大: %s MB\n",
             kv.first.c_str(), formatMb(a.pss_kb).c_str(), formatMb(a.clean_kb).c_str(),
             formatMb(a.dirty_kb).c_str(), a.maps, formatMb(a.top_kb).c_str());
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

//============================================================
// r27.83 / 24号测试补丁：native 增长探针（只读采样，默认关闭）。
// 包装按键/取候选/取上下文/上屏/切方案五个 native 入口，在每次调用前后
// 读 mallinfo.uordblks，统计"哪一类操作净增加了多少 native 分配"，
// 并把单次增量超过阈值的事件写进环形日志，供 dump 报告读取。
// 全部只读，不改任何状态；未开启时开销仅为一次 bool 判断。
//============================================================
namespace growprobe {

struct OpStat {
  const char* name;
  long calls = 0;
  long long delta_kb = 0;
  long long maxUp_kb = 0;
};

bool enabled = false;  // r27.87：非 static，与前部前向声明 extern 匹配
static long long threshold_kb = 512;
static struct timespec t0 = {0, 0};
static long long base_kb = 0;
static long long peak_kb = 0;
static OpStat stat[5] = {
    {"processKey", 0, 0, 0},
    {"getCandidates", 0, 0, 0},
    {"getContext", 0, 0, 0},
    {"commitComposition", 0, 0, 0},
    {"selectSchema", 0, 0, 0},
};

struct Event {
  long ms;
  int op;
  long long delta_kb;
  long long uord_kb;
};
static Event events[64];
static int ev_head = 0;
static int ev_count = 0;

// 注意：MallocSnap/readMalloc 定义在 memdiag 命名空间，这里必须加前缀，
// 否则即使补丁贴对位置，growprobe 命名空间内也找不到该类型(NativeGrowth编译失败)。
long long curKb() {  // r27.87：非 static，与前部前向声明匹配
  memdiag::MallocSnap m = memdiag::readMalloc();
  return m.ok ? (long long)(m.uordblks / 1024) : 0;
}

static long elapsedMs() {
  struct timespec now;
  clock_gettime(CLOCK_MONOTONIC, &now);
  if (t0.tv_sec == 0 && t0.tv_nsec == 0) return 0;
  return (long)((now.tv_sec - t0.tv_sec) * 1000 +
                (now.tv_nsec - t0.tv_nsec) / 1000000);
}

static void enable(bool on) {
  enabled = on;
  if (on) {
    clock_gettime(CLOCK_MONOTONIC, &t0);
    base_kb = curKb();
    peak_kb = base_kb;
    for (auto& s : stat) { s.calls = 0; s.delta_kb = 0; s.maxUp_kb = 0; }
    ev_head = 0; ev_count = 0;
  }
}

// 在每个包装点调用：before 为进入前采样值，op 为 stat 索引
void record(int op, long long before_kb) {  // r27.87：非 static，与前部前向声明匹配
  if (!enabled) return;
  long long after = curKb();
  if (after > peak_kb) peak_kb = after;
  long long delta = after - before_kb;
  OpStat& s = stat[op];
  s.calls += 1;
  s.delta_kb += delta;
  if (delta > s.maxUp_kb) s.maxUp_kb = delta;
  if (delta >= threshold_kb) {
    events[ev_head] = {elapsedMs(), op, delta, after};
    ev_head = (ev_head + 1) % 64;
    if (ev_count < 64) ev_count += 1;
  }
}

static std::string report() {
  char buf[256];
  std::string out;
  out.reserve(4096);
  out += "========== native 增长探针 r27.83 ==========\n";
  snprintf(buf, sizeof(buf), "状态=%s  阈值=%lldKB  已运行=%lds\n",
           enabled ? "开启" : "关闭", threshold_kb, elapsedMs() / 1000);
  out += buf;
  long long now = curKb();
  snprintf(buf, sizeof(buf), "uordblks: 起始=%lldMB 当前=%lldMB 峰值=%lldMB 净增=%+lldMB\n",
           base_kb / 1024, now / 1024, peak_kb / 1024, (now - base_kb) / 1024);
  out += buf;
  out += "\n-- 按操作聚合(调用数 / 净增 / 单次最大正增) MB --\n";
  for (const auto& s : stat) {
    snprintf(buf, sizeof(buf), "  %-18s %6ld  %+7lldMB  max+%7lldMB\n",
             s.name, s.calls, s.delta_kb / 1024, s.maxUp_kb / 1024);
    out += buf;
  }
  out += "\n-- 跳涨事件(最近, 单次>=阈值) --\n";
  if (ev_count == 0) {
    out += "  (无：没有单次操作超过阈值)\n";
  } else {
    int start = (ev_head - ev_count + 64) % 64;
    for (int i = 0; i < ev_count; ++i) {
      const Event& e = events[(start + i) % 64];
      snprintf(buf, sizeof(buf), "  +%6ldms  %-18s %+7lldMB  (uord=%lldMB)\n",
               e.ms, stat[e.op].name, e.delta_kb / 1024, e.uord_kb / 1024);
      out += buf;
    }
  }
  out += "\n说明: 净增合计若远小于 uord 净增, 说明增长发生在这些入口之外(其它 native 调用)。\n";
  return out;
}

}  // namespace growprobe

// r27.69：诊断专用——只读采集内存映射分布，返回格式化报告字符串。
// 不修改任何状态、不释放任何内存，可安全重复调用。
extern "C" JNIEXPORT jstring JNICALL
Java_com_osfans_trime_core_Rime_dumpMemoryAnalysisForDiag(JNIEnv *env,
                                                          jclass /* thiz */) {
  std::string report = memdiag::buildReport();
  return env->NewStringUTF(report.c_str());
}

// r27.83 / 24号：增长探针控制。开启后按包络统计各 native 入口的分配增量；关闭即停止采样。
extern "C" JNIEXPORT void JNICALL
Java_com_osfans_trime_core_Rime_setNativeGrowthProbeForDiag(JNIEnv *env,
                                                           jclass /* thiz */,
                                                           jboolean on) {
  growprobe::enable(on == JNI_TRUE);
}

extern "C" JNIEXPORT void JNICALL
Java_com_osfans_trime_core_Rime_setGrowthProbeThresholdForDiag(
    JNIEnv *env, jclass /* thiz */, jint threshold_kb) {
  growprobe::threshold_kb = threshold_kb > 0 ? threshold_kb : 512;
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_osfans_trime_core_Rime_dumpNativeGrowthProbeForDiag(
    JNIEnv *env, jclass /* thiz */) {
  std::string report = growprobe::report();
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

// r27.83 / 25号解决补丁：空闲安全回收。
// 仅当当前编码为空（canRecycleSession）时：
//   1) 读出当前 schema；2) 销毁 librime session（释放引擎/翻译器/词典持有的 native 活内存）；
//   3) 立即重建 session 并切回原 schema（用户无感知，下一次按键照常工作）；
//   4) 调用 M_PURGE 归还空闲页。
// 返回回收后相比回收前 uordblks 的减少量(KB)；编码非空时返回 -1 表示跳过（不打断输入）。
// 这是"大概率解决"长期 native 累积的核心：purge 只能清空闲页，而对被 session 持有的活内存
// 必须先真正销毁对象再重建，才能把 native 从 800MB 量级压回基线。
extern "C" JNIEXPORT jlong JNICALL
Java_com_osfans_trime_core_Rime_recycleIdleSessionForDiag(JNIEnv *env,
                                                          jclass /* thiz */) {
  if (!Rime::Instance().canRecycleSession()) return -1;  // 正在输入，放弃回收
  long long before = 0;
  {
    memdiag::MallocSnap m = memdiag::readMalloc();
    if (m.ok) before = (long long)m.uordblks;
  }
  std::string schema = Rime::Instance().releaseSessionForDiag();  // reset + 读 schema
  bool ok = Rime::Instance().restoreSessionForDiag(schema);        // 重建 + 切回
  // 归还空闲页（与 purgeNativeMemory 相同的 dlsym + API level 守卫）
#ifdef __ANDROID__
  if (android_get_device_api_level() >= 28) {
    using MalloptFn = int (*)(int, int);
    static MalloptFn s_mallopt = nullptr;
    static bool s_resolved = false;
    if (!s_resolved) {
      s_mallopt = reinterpret_cast<MalloptFn>(dlsym(RTLD_DEFAULT, "mallopt"));
      s_resolved = true;
    }
    if (s_mallopt) s_mallopt(-101, 0);  // M_PURGE
  }
#endif
  if (!ok) return -2;  // 重建失败
  long long after = 0;
  {
    memdiag::MallocSnap m = memdiag::readMalloc();
    if (m.ok) after = (long long)m.uordblks;
  }
  return (jlong)((before - after) / 1024);
}

// r27.88 / 26号：分配栈归因控制。开启后按调用点聚合 native 分配，dump 出 so+偏移。
extern "C" JNIEXPORT void JNICALL
Java_com_osfans_trime_core_Rime_setAllocStackProbeForDiag(JNIEnv *env,
                                                          jclass /* thiz */,
                                                          jboolean on,
                                                          jint thresholdBytes) {
  allocprobe::enable(on == JNI_TRUE, (int)thresholdBytes);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_osfans_trime_core_Rime_dumpAllocStackProbeForDiag(JNIEnv *env,
                                                           jclass /* thiz */) {
  // 先关再开：避免报告自身的 std::string/vector/dladdr 分配污染统计
  bool wasOn = allocprobe::g_enabled.load(std::memory_order_relaxed);
  allocprobe::g_enabled.store(false, std::memory_order_relaxed);
  std::string report = allocprobe::report();
  if (wasOn) allocprobe::g_enabled.store(true, std::memory_order_relaxed);
  return env->NewStringUTF(report.c_str());
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
  long long _b = growprobe::enabled ? growprobe::curKb() : 0;
  bool _r = Rime::Instance().selectSchema(*CString(env, schema_id));
  growprobe::record(4, _b);  // selectSchema
  return _r;
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
  long long _b = growprobe::enabled ? growprobe::curKb() : 0;
  jobjectArray _r = rimeCandidateListToJObjectArray(
      env, Rime::Instance().getCandidates(start_index, limit));
  growprobe::record(1, _b);  // getCandidates
  return _r;
}
