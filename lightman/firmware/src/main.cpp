/**
 * @file main.cpp
 * @brief Firmware startup, foreground event loop and local F12 setup menu.
 *
 * Coordinates the terminal, keyboard, serial transport, video and persistent settings.
 */

#include "hardware.h"
#include "hardware/clocks.h"
#include "keyboard.h"
#include "lightman_pico.h"
#include "pico/stdlib.h"
#include <algorithm>
#include <cstdio>

using namespace lightman;

namespace
{

Terminal terminal([](void *, std::string_view s) { serial_write(s); }), menu;
Keyboard keyboard;
Config config, draft;
bool in_setup = false;
int selected = 0;
constexpr int menu_items = 14;
const char *status = "";

/**
 * @brief Copy the host terminal's DECLL state to the four active-high enclosure LEDs.
 * @note The separate setup terminal never controls these outputs.
 */
void update_host_leds()
{
    uint32_t levels = 0;
    for (unsigned i = 0; i < pins::host_leds.size(); ++i)
        if (terminal.leds() & (1u << i))
            levels |= 1u << pins::host_leds[i];
    gpio_put_masked(pins::host_led_mask, levels);
}

/**
 * @brief Rebuild the local setup screen from draft settings and live diagnostics.
 * @note Leaves the host terminal screen unchanged; core 0 later publishes the menu.
 */
void draw_menu()
{
    menu.reset();
    menu.feed("\033[?25l\033[2;4H\033[1mLIGHTMAN SETUP\033[0m");

    const char *flow[] = {"None (TX/RX only)", "XON/XOFF", "RTS/CTS (wire handshake pins)"};
    const char *parity[] = {"None", "Even", "Odd"};

    char lines[menu_items][70];
    std::snprintf(lines[0], 70, "Baud rate       %lu", static_cast<unsigned long>(draft.baud));
    std::snprintf(lines[1], 70, "Data bits       %u", draft.data_bits);
    std::snprintf(lines[2], 70, "Parity          %s", parity[draft.parity]);
    std::snprintf(lines[3], 70, "Stop bits       %u", draft.stop_bits);
    std::snprintf(lines[4], 70, "Flow control    %s", flow[static_cast<unsigned>(draft.flow)]);
    std::snprintf(lines[5], 70, "Terminal        %s", draft.vt52 ? "VT52" : "VT100");
    std::snprintf(lines[6], 70, "Local echo      %s", draft.echo ? "On" : "Off");
    std::snprintf(lines[7], 70, "Backspace sends %s", draft.backspace_del ? "DEL (127)" : "BS (8)");
    std::snprintf(lines[8], 70, "Font            %s", draft.font ? "Bold" : "Regular");
    std::snprintf(lines[9], 70, "Normal color    %s", normal_colors[draft.color].name);
    std::snprintf(lines[10], 70, "Columns         %u", draft.columns);
    std::snprintf(lines[11], 70, "Receive CR+LF   %s", draft.receive_crlf ? "On" : "Off");
    std::snprintf(lines[12], 70, "Transmit CR+LF  %s", draft.transmit_crlf ? "On" : "Off");
    std::snprintf(lines[13], 70, "Restore factory defaults");

    for (int i = 0; i < menu_items; ++i)
    {
        char pos[24];
        std::snprintf(pos, sizeof pos, "\033[%d;4H", i + 4);
        menu.feed(pos);
        if (i == selected)
            menu.feed("\033[7m");
        menu.feed(lines[i]);
        menu.feed("\033[0m");
    }

    menu.feed("\033[18;4HUp/Down: select   Left/Right/Space: change");
    menu.feed("\033[19;4HEnter: apply   S: apply and save   Esc/F12: cancel");
    menu.feed("\033[20;4HPause host output before changing serial settings or saving.");
    menu.feed("\033[21;4HSaving briefly blanks VGA. Mode changes clear terminal text.");

    char counters[100];
    std::snprintf(counters, sizeof counters, "\033[22;4HRX errors:%lu  TX drops:%lu  PS/2 drops:%lu  VGA late:%lu",
                  (unsigned long)serial_rx_errors(), (unsigned long)serial_tx_drops(), (unsigned long)ps2_overflows(),
                  (unsigned long)video_underruns());
    menu.feed(counters);
    menu.feed("\033[23;4H");
    menu.feed(status);
    menu.feed("\033[24;4H");
    menu.feed(serial_dsr() ? "DSR: asserted" : "DSR: inactive");
    menu.feed(serial_dcd() ? "  DCD: asserted" : "  DCD: inactive");
    menu.feed(serial_ri() ? "  RI: asserted" : "  RI: inactive");
}

/**
 * @brief Cycle the selected draft option or restore draft factory defaults.
 * @param direction Use -1 for the previous choice or +1 for the next.
 * @note Does not apply settings to hardware or write flash.
 */
void change(int direction)
{
    auto cycle = [direction](uint8_t &value, int count) { value = (value + count + direction) % count; };
    switch (selected)
    {
    case 0: {
        auto i = std::find(baud_rates.begin(), baud_rates.end(), draft.baud) - baud_rates.begin();
        draft.baud = baud_rates[(i + baud_rates.size() + direction) % baud_rates.size()];
        break;
    }
    case 1:
        draft.data_bits = draft.data_bits == 8 ? 7 : 8;
        break;
    case 2:
        cycle(draft.parity, 3);
        break;
    case 3:
        draft.stop_bits = draft.stop_bits == 1 ? 2 : 1;
        break;
    case 4:
        draft.flow = static_cast<Flow>((int(draft.flow) + 3 + direction) % 3);
        break;
    case 5:
        draft.vt52 ^= 1;
        break;
    case 6:
        draft.echo ^= 1;
        break;
    case 7:
        draft.backspace_del ^= 1;
        break;
    case 8:
        cycle(draft.font, 2);
        break;
    case 9:
        cycle(draft.color, normal_colors.size());
        break;
    case 10:
        draft.columns = draft.columns == 80 ? 132 : 80;
        break;
    case 11:
        draft.receive_crlf ^= 1;
        break;
    case 12:
        draft.transmit_crlf ^= 1;
        break;
    case 13:
        draft = Config{};
        break;
    }
}

/**
 * @brief Close setup, clear its status text and release the peer-pause request.
 */
void close_menu()
{
    in_setup = false;
    status = "";
    serial_hold(false);
}

/**
 * @brief Service serial RX/TX while waiting up to 1.5 seconds for TX to drain.
 * @return True once both the TX queue and UART are idle; false on timeout.
 * @note Incoming bytes continue updating the terminal during this foreground wait.
 */
bool drain_transmitter()
{
    uint32_t start = time_us_32();
    do
    {
        for (int i = 0; i < 4096; ++i)
        {
            int c = serial_read();
            if (c < 0)
                break;
            terminal.feed(static_cast<uint8_t>(c), config.receive_crlf);
        }
        update_host_leds();
        serial_poll();
        if (serial_idle())
            return true;
        sleep_ms(1);
    } while (time_us_32() - start < 1500000);
    return false;
}

/**
 * @brief Handle setup navigation, cancellation, application and optional persistence.
 * @param e Decoded local key press.
 * @note Reports flow-control or flash failures in the menu and keeps setup open.
 */
void setup_key(KeyEvent e)
{
    if (e.key == Key::Escape || e.key == Key::Setup)
    {
        close_menu();
        return;
    }
    if (e.key == Key::Up)
        selected = (selected + menu_items - 1) % menu_items;
    if (e.key == Key::Down)
        selected = (selected + 1) % menu_items;
    if (e.key == Key::Left)
        change(-1);
    if (e.key == Key::Right || (e.key == Key::Character && e.character == ' '))
        change(1);
    bool save = e.key == Key::Character && (e.character == 's' || e.character == 'S');
    if (e.key == Key::Enter || save)
    {
        // Release old software flow control before changing baud/framing/mode.
        serial_hold(false);
        if (!drain_transmitter())
        {
            serial_hold(true);
            status = "TX blocked: restore host CTS/XON, then retry.";
            return;
        }
        if (save)
        {
            serial_hold(true);
            serial_poll();
            // Wait for XOFF to leave even at 300 baud, then allow host reaction.
            if (!drain_transmitter())
            {
                status = "TX blocked; settings have not been saved.";
                return;
            }
            sleep_ms(100);
            if (!settings_save(draft))
            {
                status = "Flash verification failed; changes not applied.";
                return;
            }
            serial_hold(false);
            serial_poll();
            if (!drain_transmitter())
            {
                status = "Saved; TX busy. Retry apply or reboot.";
                return;
            }
        }
        if (!serial_apply(draft))
        {
            serial_hold(true);
            status = "TX still busy; retry.";
            return;
        }
        if (config.vt52 != draft.vt52)
            terminal.reset(draft.vt52, draft.columns);
        else if (terminal.column_count() != draft.columns)
            terminal.set_columns(draft.columns);
        config = draft;
        close_menu();
    }
}
} // namespace

/**
 * @brief Initialize the Pico and run the terminal, keyboard and setup event loop.
 * @note Runs on core 0 and does not return; video_start() launches scanout on core 1.
 */
int main()
{
    set_sys_clock_khz(126000, true);
    config = settings_load();
    terminal.reset(config.vt52, config.columns);
    for (unsigned pin : pins::host_leds)
    {
        gpio_init(pin);
        gpio_put(pin, false); // Load the off level before enabling the output driver.
        gpio_set_drive_strength(pin, GPIO_DRIVE_STRENGTH_2MA);
        gpio_set_dir(pin, GPIO_OUT);
    }
    serial_start(config);
    ps2_start();
    video_start();
    gpio_init(PICO_DEFAULT_LED_PIN);
    gpio_set_dir(PICO_DEFAULT_LED_PIN, GPIO_OUT);
    terminal.feed("Lightman 0.1 - F12 opens setup\r\n");
    uint32_t last_frame = 0, last_ps2_drops = 0, last_bells = 0, bell_at = 0;
    bool bell_on = false;

    while (true)
    {
        serial_poll();

        // Continue receiving into the terminal while the separate setup screen is
        // shown.
        for (int i = 0; i < 256; ++i)
        {
            int c = serial_read();
            if (c < 0)
                break;
            terminal.feed(static_cast<uint8_t>(c), config.receive_crlf);
        }

        auto drops = ps2_overflows();
        if (drops != last_ps2_drops)
        {
            keyboard.reset();
            last_ps2_drops = drops;
        }

        for (int i = 0; i < 32; ++i)
        {
            int c = ps2_read();
            if (c < 0)
                break;
            auto e = keyboard.feed(c);
            if (e.key == Key::None)
                continue;
            if (in_setup)
                setup_key(e);
            else if (e.key == Key::Setup)
            {
                in_setup = true;
                draft = config;
                draft.columns = terminal.column_count();
                selected = 0;
                status = "";
                serial_hold(true);
            }
            else if (!terminal.keyboard_locked())
            {
                auto text = encode_key(e, terminal, config.backspace_del, config.transmit_crlf);
                serial_write(text);
                if (config.echo)
                    terminal.feed(text);
            }
        }

        uint32_t now = time_us_32();
        if (terminal.bells != last_bells)
        {
            last_bells = terminal.bells;
            bell_at = now;
            bell_on = true;
        }
        if (bell_on && now - bell_at >= 150000)
            bell_on = false;

        gpio_put(PICO_DEFAULT_LED_PIN, bell_on);
        update_host_leds();

        if (now - last_frame >= 16667)
        {
            last_frame = now;
            if (in_setup)
            {
                draw_menu();
                video_publish(menu, draft);
            }
            else
                video_publish(terminal, config);
        }
        tight_loop_contents();
    }
}
