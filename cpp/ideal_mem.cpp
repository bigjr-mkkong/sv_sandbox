#include <cstdint>
#include <map>

#include <svdpi.h>

namespace {

struct cacheline {
    std::uint16_t line_data;
};

class cpp_ideal_mem {
  public:
    void reset() {
        mem.clear();
    }

    void write_data(std::uint32_t addr, const cacheline& data) {
        mem[normalize_address(addr)] = data;
    }

    cacheline read_data(std::uint32_t addr) const {
        const auto entry = mem.find(normalize_address(addr));
        if (entry == mem.end()) {
            return {};
        }
        return entry->second;
    }

  private:
    static std::uint32_t normalize_address(std::uint32_t addr) {
        return addr & ~std::uint32_t{1};
    }

    std::map<std::uint32_t, cacheline> mem;
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
    unsigned int addr,
    const svBitVecVal* data
) {
    if (handle == nullptr || data == nullptr) {
        return;
    }

    cacheline line{};
    line.line_data = static_cast<std::uint16_t>(data[0]);
    as_memory(handle)->write_data(static_cast<std::uint32_t>(addr), line);
}

extern "C" void ideal_mem_read(
    void* handle,
    unsigned int addr,
    svBitVecVal* data
) {
    if (data == nullptr) {
        return;
    }

    data[0] = 0;
    if (handle == nullptr) {
        return;
    }

    const cacheline line = as_memory(handle)->read_data(static_cast<std::uint32_t>(addr));
    data[0] = static_cast<svBitVecVal>(line.line_data);
}
