/**
 * @file flash_limit.ld
 * @brief Linker guard for the Pico settings sectors.
 *
 * Rejects firmware images that reach the reserved flash area at address 0x101FE000.
 */
/* Original 2 MiB Pico: keep the last two sectors out of the firmware image. */
SECTIONS {
    .lightman_flash_limit : {
        ASSERT(__flash_binary_end <= 0x101fe000, "Lightman firmware overlaps settings sectors");
    }
}
INSERT AFTER .flash_end;
