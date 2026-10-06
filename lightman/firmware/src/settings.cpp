/**
 * @file settings.cpp
 * @brief Persistent settings in two alternating flash sectors.
 *
 * Reserves the final two 4 KiB sectors of the original 2 MiB Pico. A save parks
 * core 1 in SRAM and disables core 0 interrupts while flash is erased/programmed.
 */
#include "hardware.h"
#include "hardware/flash.h"
#include "hardware/sync.h"
#include "pico/stdlib.h"
#include <algorithm>
#include <cstring>
namespace lightman
{
namespace
{
constexpr uint32_t storage_offset = 2 * 1024 * 1024 - 2 * FLASH_SECTOR_SIZE;
int slot = -1;
uint32_t generation = 0;
} // namespace
/**
 * @brief Select and decode the newest valid flash settings record.
 */
Config settings_load()
{
    Config result;
    for (int i = 0; i < 2; ++i)
    {
        Config candidate;
        uint32_t g;
        auto *p = reinterpret_cast<const uint8_t *>(XIP_BASE + storage_offset + i * FLASH_SECTOR_SIZE);
        if (decode_config(p, candidate, g) && (slot < 0 || static_cast<int32_t>(g - generation) > 0))
        {
            result = candidate;
            generation = g;
            slot = i;
        }
    }
    return result;
}
/**
 * @brief Save validated settings to the alternate flash sector and verify the write.
 */
bool settings_save(const Config &config)
{
    if (!config.valid())
        return false;
    auto encoded = encode_config(config, generation + 1);
    alignas(4) uint8_t page[FLASH_PAGE_SIZE];
    std::fill_n(page, sizeof page, 0xff);
    std::copy(encoded.begin(), encoded.end(), page);
    int next = slot == 0 ? 1 : 0;
    uint32_t offset = storage_offset + next * FLASH_SECTOR_SIZE;
    video_pause();
    uint32_t irq = save_and_disable_interrupts();
    flash_range_erase(offset, FLASH_SECTOR_SIZE);
    flash_range_program(offset, page, sizeof page);
    restore_interrupts(irq);
    video_resume();
    bool ok = std::memcmp(reinterpret_cast<const void *>(XIP_BASE + offset), page, sizeof page) == 0;
    if (ok)
    {
        slot = next;
        ++generation;
    }
    return ok;
}
} // namespace lightman
