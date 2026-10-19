#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <map>
#include <memory>

#include <svdpi.h>

namespace {

struct data_blk {
    std::unique_ptr<std::byte[]> data;
};

class cpp_ideal_mem {
  public:
    explicit cpp_ideal_mem(std::size_t data_width) : data_width(data_width) {}

    void reset() {
        mem.clear();
    }

    void write_data(std::uint32_t addr, const svBitVecVal* data) {
        auto& block = mem[normalize_address(addr)];
        if (!block.data) {
            block.data = std::make_unique<std::byte[]>(data_width / 8);
        }
        for (std::size_t i = 0; i < data_width / 8; ++i) {
            block.data[i] = static_cast<std::byte>((data[i / 4] >> (8 * (i % 4))) & 0xff);
        }
    }

    void read_data(std::uint32_t addr, svBitVecVal* data) const {
        std::fill_n(data, (data_width + 31) / 32, svBitVecVal{0});
        const auto entry = mem.find(normalize_address(addr));
        if (entry == mem.end()) {
            return;
        }
        for (std::size_t i = 0; i < data_width / 8; ++i) {
            data[i / 4] |= std::to_integer<svBitVecVal>(entry->second.data[i]) << (8 * (i % 4));
        }
    }

  private:
    std::size_t normalize_address(std::uint32_t addr) const {
        const auto byte_width = data_width / 8;
        return addr - addr % byte_width;
    }

    const std::size_t data_width;
    std::map<std::size_t, data_blk> mem;
};

cpp_ideal_mem* as_memory(void* handle) {
    return static_cast<cpp_ideal_mem*>(handle);
}

}  // namespace

// Width is in bits; accesses use byte addresses aligned to one data block.
extern "C" void* ideal_mem_create(unsigned int data_width) {
    if (data_width == 0 || data_width % 8 != 0) {
        return nullptr;
    }
    return new cpp_ideal_mem(data_width);
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
    if (handle != nullptr && data != nullptr) {
        as_memory(handle)->write_data(addr, data);
    }
}

extern "C" void ideal_mem_read(
    void* handle,
    unsigned int addr,
    svBitVecVal* data
) {
    if (data == nullptr) {
        return;
    }
    if (handle == nullptr) {
        data[0] = 0;
        return;
    }
    as_memory(handle)->read_data(addr, data);
}
