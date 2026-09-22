#pragma once
#include "joshua/memory.hpp"
#include <ostream>
#include <stdexcept>
#include <string>

namespace joshua
{
    enum class ConsoleNewline
    {
        raw,
        cr,
        lf,
        automatic
    };

    inline ConsoleNewline parseConsoleNewline(const std::string &value)
    {
        if (value == "raw")
            return ConsoleNewline::raw;
        if (value == "cr")
            return ConsoleNewline::cr;
        if (value == "lf")
            return ConsoleNewline::lf;
        if (value == "auto")
            return ConsoleNewline::automatic;
        throw std::runtime_error("console-newline must be raw, cr, lf or auto");
    }
    inline const char *consoleNewlineName(ConsoleNewline mode)
    {
        switch (mode)
        {
        case ConsoleNewline::cr:
            return "cr";
        case ConsoleNewline::lf:
            return "lf";
        case ConsoleNewline::automatic:
            return "auto";
        default:
            return "raw";
        }
    }

    // Host presentation only: ACIA frames and received bytes remain untouched.
    class ConsoleOutput
    {
    public:
        explicit ConsoleOutput(ConsoleNewline mode = ConsoleNewline::raw) : mode_(mode) {}
        ConsoleNewline mode() const { return mode_; }
        void setMode(ConsoleNewline mode)
        {
            mode_ = mode;
            previousCr_ = false;
        }
        void write(std::ostream &out, Byte value)
        {
            const bool expandCr = mode_ == ConsoleNewline::cr || mode_ == ConsoleNewline::automatic;
            const bool expandLf = mode_ == ConsoleNewline::lf || mode_ == ConsoleNewline::automatic;
            if (value == '\r' && expandCr)
                out << "\r\n";
            else if (value == '\n' && previousCr_ && expandCr)
            {
            } // CR already advanced the line.
            else if (value == '\n' && !previousCr_ && expandLf)
                out << "\r\n";
            else
                out.put(static_cast<char>(value));
            previousCr_ = value == '\r';
        }

    private:
        ConsoleNewline mode_;
        bool previousCr_ = false;
    };
}
