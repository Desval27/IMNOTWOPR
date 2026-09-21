#pragma once
#include <memory>
#include <optional>

// All host console APIs stay outside the portable emulation library.
class Terminal {
public:
    Terminal();
    ~Terminal();
    Terminal(const Terminal&) = delete;
    Terminal& operator=(const Terminal&) = delete;
    bool interactive() const;
    std::optional<unsigned char> poll();
    bool eof() const;
private:
    struct State;
    std::unique_ptr<State> state_;
};
