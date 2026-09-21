cmake_minimum_required(VERSION 3.24)
project(joshua VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

add_library(joshua_core
    lib/memory.cpp lib/devices.cpp lib/cpu.cpp lib/instruction.cpp
    lib/config.cpp lib/machine.cpp lib/monitor.cpp)
target_include_directories(joshua_core PUBLIC include)
if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_options(joshua_core PRIVATE -Wall -Wextra -Wpedantic)
endif()

add_executable(joshua app/main.cpp app/terminal.cpp)
target_link_libraries(joshua PRIVATE joshua_core)

include(CTest)
if(BUILD_TESTING)
    add_executable(joshua_tests tests/tests.cpp)
    target_link_libraries(joshua_tests PRIVATE joshua_core)
    add_test(NAME core COMMAND joshua_tests)
    add_test(NAME cli_help COMMAND joshua --help)
    add_executable(joshua_vectors tests/vectors.cpp)
    target_link_libraries(joshua_vectors PRIVATE joshua_core)
    find_package(Python3 COMPONENTS Interpreter QUIET)
    if(Python3_Interpreter_FOUND)
        add_test(NAME integration COMMAND "${Python3_EXECUTABLE}"
            "${CMAKE_CURRENT_SOURCE_DIR}/tests/integration.py" "$<TARGET_FILE:joshua>")
    endif()
endif()

install(TARGETS joshua RUNTIME DESTINATION bin)
