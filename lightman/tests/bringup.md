# Hardware acceptance checks

Desktop tests and cross-compilation do not verify electrical or real-time
behavior. Perform these checks before relying on the prototype.

1. Confirm the pin map in [wiring](../docs/wiring.md), level-shifter supplies,
   PS/2 pull-ups, all three MAX3232 charge pumps and VGA resistor values.
   Confirm TX/RX reach GPIO0/1, CTS/RTS GPIO2/3 and DTR/DSR GPIO5/4.
   Confirm DCD/RI reach GPIO6/7 and PS/2 clock/data reach GPIO8/9.
   Confirm HS/VS reach GPIO13/14, R0..R2 GPIO15..17, G0..G2 GPIO18..20 and
   B0..B1 GPIO21/22. Channel 0 must feed the smallest resistor (greatest weight).
2. Flash the UF2. Confirm 31.5 kHz HSYNC and 60 Hz VSYNC, negative polarity,
   proper RGB blanking and a stable 80x24 picture. `VGA late` in setup should
   stay zero during scrolling, keyboard activity and repeated menu changes.
   In setup select White and check all three color channels near 0.7 V into
   75 ohms on lit pixels; black, porches and sync must blank all eight RGB bits.
   Check Red/Classic green/Blue for isolated channels, then Amber for full red,
   G0 only and blue off. Amber should differ visibly from Yellow.
3. On a native PS/2 keyboard check letters, digits, shifted punctuation,
   independent left/right Shift and Ctrl, Caps Lock, Ctrl-C, arrow/PF keys,
   keypad application mode, and F12 setup. Disconnect/reconnect and verify BAT
   resets modifiers. Check parity/timeout recovery using a signal generator
   if available. No LED updates are expected on the keyboard itself.
4. Connect DE-9 TX/RX loopback (pins 3/2), default 9600 8N1, local echo off.
   Typed characters should return once. Then test a null-modem-connected host.
5. At each supported baud/framing combination, match the host settings and
   send known patterns. Test 115200-baud sustained text, full-screen scrolling,
   cursor addressing, reverse/underline/blink, and simultaneous keyboard use.
   Monitor RX/TX errors and VGA late counts.
6. Test XON/XOFF in both directions. Send XOFF while typing, then XON; queued
   keys must arrive in order. Open/close setup and confirm the host pauses and
   resumes. A host that ignores flow control may overflow RX; verify the
   counter reports it. Repeated settings changes must not strand the peer in
   XOFF state.
7. Wire RTS/CTS and test gating with CTS deasserted. Resume CTS and verify
   queued characters arrive. Confirm RTS deasserts under RX pressure/setup,
   DTR stays asserted, and DSR status follows the input. Independently assert
   and deassert DCD (DE-9 pin 1) and RI (pin 9) through their receivers: setup
   must show each asserted when its GPIO is low and inactive when high.
   Confirm serial traffic and keyboard input continue in both states. Hold RI
   long enough to observe a display update; its status is not latched.
   No CTS wiring means hardware flow control should remain disabled.
8. Send `ESC [ ? 2 l`, test VT52 cursor addressing and identity, then `ESC <`
   to return to VT100. Run the host's VT100 test program and compare failures
   to the [declared gaps](../docs/compatibility.md); do not claim full vttest
   compliance.
9. In setup cycle all eight Normal color choices in both directions, including
   wraparound. Confirm the preview, cancel, then apply; cancel must restore the
   previous display. Check reverse, bold, underline, blink and cursor in the
   selected color. Restore factory defaults and verify Amber is selected;
   cancel must retain the previous configuration. Apply/save factory defaults
   and verify Amber after reboot. Existing saved White/Green/Yellow choices
   should survive the firmware update. Save settings, power-cycle, verify
   persistence. Alternate
   saved configurations and interrupt power during a save: the last intact
   record should load. Reflash UF2 and check settings remain intact.
10. After flash save verify video recovers, the keyboard still works and serial
    flow resumes. Test with the host paused; separately establish how a peer
    ignoring the pause affects RX error counts.

For a host serial smoke test (replace the serial device as appropriate):

```sh
stty -F /dev/ttyUSB0 9600 cs8 -parenb -cstopb -crtscts -ixon -ixoff raw -echo
printf '\033[2J\033[HLightman test\r\n\033[7mReverse\033[0m\r\n' > /dev/ttyUSB0
printf '\033(0lqqqqk\r\nx    x\r\nmqqqqj\033(B\r\n' > /dev/ttyUSB0
```
