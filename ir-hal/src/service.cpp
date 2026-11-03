// android.hardware.ir AIDL HAL for the Samsung Galaxy Note 10.1 2014 (n1awifi).
// The kernel driver takes "carrier,count,count,..." where counts are carrier
// cycles; Android gives the pattern in microseconds, so we convert.
#include <aidl/android/hardware/ir/BnConsumerIr.h>
#include <android/binder_manager.h>
#include <android/binder_process.h>
#include <android/log.h>

#include <cerrno>
#include <cmath>
#include <cstring>
#include <fcntl.h>
#include <string>
#include <unistd.h>

#define LOG_TAG "ir-n1awifi"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

using aidl::android::hardware::ir::BnConsumerIr;
using aidl::android::hardware::ir::ConsumerIrFreqRange;

static const char* kIrSend = "/sys/class/sec/sec_ir/ir_send";
static const size_t kMaxBuf = 4000;  // sysfs store is one page

class ConsumerIr : public BnConsumerIr {
  public:
    ndk::ScopedAStatus getCarrierFreqs(std::vector<ConsumerIrFreqRange>* out) override {
        out->clear();
        out->push_back({.minHz = 30000, .maxHz = 60000});
        return ndk::ScopedAStatus::ok();
    }

    ndk::ScopedAStatus transmit(int32_t carrierFreqHz, const std::vector<int32_t>& pattern) override {
        if (carrierFreqHz < 30000 || carrierFreqHz > 60000 || pattern.empty())
            return ndk::ScopedAStatus::fromExceptionCode(EX_UNSUPPORTED_OPERATION);
        std::string buf = std::to_string(carrierFreqHz);
        int64_t totalUs = 0;
        for (int32_t us : pattern) {
            if (us < 0) return ndk::ScopedAStatus::fromExceptionCode(EX_ILLEGAL_ARGUMENT);
            totalUs += us;
            long cycles = std::lround((double)us * carrierFreqHz / 1000000.0);
            buf += "," + std::to_string(cycles < 1 ? 1 : cycles);
        }
        if (buf.size() > kMaxBuf) {
            LOGE("pattern too long (%zu bytes)", buf.size());
            return ndk::ScopedAStatus::fromExceptionCode(EX_ILLEGAL_ARGUMENT);
        }
        int fd = open(kIrSend, O_WRONLY | O_CLOEXEC);
        if (fd < 0) {
            LOGE("open %s: %s", kIrSend, strerror(errno));
            return ndk::ScopedAStatus::fromServiceSpecificError(errno);
        }
        ssize_t n = write(fd, buf.c_str(), buf.size());
        int err = errno;
        close(fd);
        if (n < 0) {
            LOGE("write: %s", strerror(err));
            return ndk::ScopedAStatus::fromServiceSpecificError(err);
        }
        // ConsumerIrManager.transmit() blocks until the signal is sent.
        usleep((useconds_t)std::min<int64_t>(totalUs, 2000000));
        return ndk::ScopedAStatus::ok();
    }
};

int main(int argc, char** argv) {
    if (argc == 2 && std::string(argv[1]) == "--test") {  // send a NEC-like burst without binder
        auto ir = ndk::SharedRefBase::make<ConsumerIr>();
        auto st = ir->transmit(38000, {9000, 4500, 560, 560, 560, 1690, 560, 40000});
        return st.isOk() ? 0 : 1;
    }
    ABinderProcess_setThreadPoolMaxThreadCount(0);
    auto ir = ndk::SharedRefBase::make<ConsumerIr>();
    const std::string name = std::string(ConsumerIr::descriptor) + "/default";
    binder_status_t st = AServiceManager_addService(ir->asBinder().get(), name.c_str());
    if (st != STATUS_OK) {
        LOGE("addService %s failed: %d", name.c_str(), st);
        return 1;
    }
    LOGI("registered %s", name.c_str());
    ABinderProcess_joinThreadPool();
    return 1;
}
