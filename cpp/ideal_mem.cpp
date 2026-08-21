#include <cstddef>
#include <cstdint>
#include <map>

#include <svdpi.h>

namespace {

constexpr std::uint64_t kCachelineBytes = 64;
constexpr std::size_t kWordsPerCacheline = 8;
constexpr std::size_t kDpiWordsPerCacheline = 16;

struct cacheline {
    std::uint64_t line_data[kWordsPerCacheline];
};

class cpp_ideal_mem {
  public:
    void reset() {
        mem.clear();
    }

    void write_data(std::uint64_t addr, const cacheline& data) {
        mem[normalize_address(addr)] = data;
    }

    cacheline read_data(std::uint64_t addr) const {
        const auto entry = mem.find(normalize_address(addr));
        if (entry == mem.end()) {
            return {};
        }
        return entry->second;
    }

  private:
    static std::uint64_t normalize_address(std::uint64_t addr) {
        return addr & ~(kCachelineBytes - 1);
    }

    std::map<std::uint64_t, cacheline> mem;
};

cpp_ideal_mem* as_memory(void* handle) {
    return static_cast<cpp_ideal_mem*>(handle);
}

}  // namespace

extern "C" void* ideal_mem_create() {
    return new cpp_ideal_mem();
}

extern "C" void ideal_mem_destroy(void* handle) {
    delete as_memory(handle);
}

extern "C" void ideal_mem_reset(void* handle) {
    if (handle != nullptr) {
        as_memory(handle)->reset();
    }
}

extern "C" void ideal_mem_write(
    void* handle,
    unsigned long long addr,
    const svBitVecVal* data
) {
    if (handle == nullptr || data == nullptr) {
        return;
    }

    cacheline line{};
    for (std::size_t word = 0; word < kWordsPerCacheline; ++word) {
        const std::size_t dpi_word = word * 2;
        line.line_data[word] =
            std::uint64_t{data[dpi_word]}
            | (std::uint64_t{data[dpi_word + 1]} << 32);
    }
    as_memory(handle)->write_data(static_cast<std::uint64_t>(addr), line);
}

extern "C" void ideal_mem_read(
    void* handle,
    unsigned long long addr,
    svBitVecVal* data
) {
    if (data == nullptr) {
        return;
    }

    for (std::size_t word = 0; word < kDpiWordsPerCacheline; ++word) {
        data[word] = 0;
    }
    if (handle == nullptr) {
        return;
    }

    const cacheline line =
        as_memory(handle)->read_data(static_cast<std::uint64_t>(addr));
    for (std::size_t word = 0; word < kWordsPerCacheline; ++word) {
        const std::size_t dpi_word = word * 2;
        data[dpi_word] = static_cast<svBitVecVal>(line.line_data[word]);
        data[dpi_word + 1] =
            static_cast<svBitVecVal>(line.line_data[word] >> 32);
    }
}
