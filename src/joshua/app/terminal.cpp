#include "terminal.hpp"
#include <stdexcept>
#ifdef _WIN32
#define NOMINMAX
#include <windows.h>
#else
#include <cerrno>
#include <poll.h>
#include <termios.h>
#include <unistd.h>
#endif

struct Terminal::State {
    bool tty = false, ended = false;
#ifdef _WIN32
    HANDLE input = GetStdHandle(STD_INPUT_HANDLE);
    DWORD oldMode = 0;
#else
    termios oldMode{};
#endif
};
Terminal::Terminal() : state_(std::make_unique<State>()) {
#ifdef _WIN32
    state_->tty = GetConsoleMode(state_->input, &state_->oldMode) != 0;
    if (state_->tty && !SetConsoleMode(state_->input, state_->oldMode & ~(ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT | ENABLE_PROCESSED_INPUT)))
        throw std::runtime_error("cannot enter raw console mode");
#else
    state_->tty = isatty(STDIN_FILENO);
    if (state_->tty) {
        if (tcgetattr(STDIN_FILENO, &state_->oldMode)) throw std::runtime_error("cannot read terminal settings");
        auto mode = state_->oldMode;
        mode.c_iflag &= ~(IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON);
        mode.c_lflag &= ~(ECHO | ECHONL | ICANON | ISIG | IEXTEN);
        mode.c_cflag = (mode.c_cflag & ~(CSIZE | PARENB)) | CS8;
        mode.c_cc[VMIN] = 0; mode.c_cc[VTIME] = 0;
        if (tcsetattr(STDIN_FILENO, TCSANOW, &mode)) throw std::runtime_error("cannot enter raw terminal mode");
    }
#endif
}
Terminal::~Terminal() {
#ifdef _WIN32
    if (state_->tty) SetConsoleMode(state_->input, state_->oldMode);
#else
    if (state_->tty) tcsetattr(STDIN_FILENO, TCSANOW, &state_->oldMode);
#endif
}
bool Terminal::interactive() const { return state_->tty; }
bool Terminal::eof() const { return state_->ended; }
std::optional<unsigned char> Terminal::poll() {
    if (!state_->tty) return std::nullopt;
#ifdef _WIN32
    if (state_->tty) {
        DWORD count = 0;
        if (!GetNumberOfConsoleInputEvents(state_->input, &count) || !count) return std::nullopt;
        INPUT_RECORD event{};
        if (!ReadConsoleInputA(state_->input, &event, 1, &count)) throw std::runtime_error("console input failed");
        if (event.EventType == KEY_EVENT && event.Event.KeyEvent.bKeyDown && event.Event.KeyEvent.uChar.AsciiChar)
            return static_cast<unsigned char>(event.Event.KeyEvent.uChar.AsciiChar);
    }
#else
    pollfd fd{STDIN_FILENO, POLLIN, 0};
    int ready = ::poll(&fd, 1, 0);
    if (ready < 0 && errno != EINTR) throw std::runtime_error("terminal poll failed");
    if (ready > 0 && (fd.revents & (POLLIN | POLLHUP))) {
        unsigned char value;
        auto count = ::read(STDIN_FILENO, &value, 1);
        if (count == 1) return value;
        if (count == 0) state_->ended = true;
        else if (errno != EINTR && errno != EAGAIN) throw std::runtime_error("terminal read failed");
    }
#endif
    return std::nullopt;
}
