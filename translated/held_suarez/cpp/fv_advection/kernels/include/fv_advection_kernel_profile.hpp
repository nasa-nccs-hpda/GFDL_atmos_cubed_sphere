#ifndef FV_ADVECTION_KERNEL_PROFILE_HPP
#define FV_ADVECTION_KERNEL_PROFILE_HPP

#include <chrono>
#include <cstdlib>
#include <cstdio>
#include <cstring>

namespace fv_advection_kernels_profile {

struct Counter {
    const char* name;
    long long calls;
    double seconds;
};

inline bool enabled() {
    const char* value = std::getenv("FV_KERNELS_PROFILE");
    return value != nullptr && std::strcmp(value, "0") != 0 &&
           std::strcmp(value, "false") != 0 &&
           std::strcmp(value, "FALSE") != 0 &&
           std::strcmp(value, "off") != 0 &&
           std::strcmp(value, "OFF") != 0;
}

inline const char* rank_string() {
    const char* rank = std::getenv("OMPI_COMM_WORLD_RANK");
    if (rank == nullptr) {
        rank = std::getenv("PMI_RANK");
    }
    if (rank == nullptr) {
        rank = std::getenv("MPI_RANKID");
    }
    return rank == nullptr ? "unknown" : rank;
}

inline void record(Counter& counter, double seconds) {
    if (!enabled()) {
        return;
    }
    counter.calls += 1;
    counter.seconds += seconds;
}

inline void print_counter(const char* backend, const Counter& counter) {
    if (!enabled() || counter.calls <= 0) {
        return;
    }
    const double avg = counter.seconds / static_cast<double>(counter.calls);
    std::fprintf(
        stdout,
        "PROFILE_FV_ADVECTION_KERNEL backend=%s rank=%s name=%s calls=%lld time=%.9f avg=%.9e\n",
        backend,
        rank_string(),
        counter.name,
        counter.calls,
        counter.seconds,
        avg);
    std::fflush(stdout);
}

class ScopedTimer {
  public:
    explicit ScopedTimer(Counter& counter)
        : counter_(counter),
          active_(enabled()),
          start_(std::chrono::steady_clock::now()) {}

    ~ScopedTimer() {
        if (!active_) {
            return;
        }
        const auto stop = std::chrono::steady_clock::now();
        const double seconds =
            std::chrono::duration<double>(stop - start_).count();
        record(counter_, seconds);
    }

  private:
    Counter& counter_;
    bool active_;
    std::chrono::steady_clock::time_point start_;
};

}  // namespace fv_advection_kernels_profile

#endif  // FV_ADVECTION_KERNEL_PROFILE_HPP
