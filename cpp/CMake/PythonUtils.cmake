
# Helpers
function(_python_utils_dump_vars_targets _target _props)
    if(TARGET ${_target})
        foreach(prop ${_props})
            get_property(prop_set TARGET ${_target} PROPERTY ${prop} SET)
            if(prop_set)
                get_target_property(val ${_target} ${prop})
                message("${_target} ${prop}=${val}")
            endif()
        endforeach()
    endif()
endfunction()

function(python_utils_dump_vars _message)
    message("${_message}")

    if(NOT CMAKE_PROPERTY_LIST)
        execute_process(COMMAND cmake --help-property-list OUTPUT_VARIABLE CMAKE_PROPERTY_LIST)
        string(REGEX REPLACE "\n" ";" CMAKE_PROPERTY_LIST "${CMAKE_PROPERTY_LIST}")
        set(CMAKE_INTERFACE_PROPERTY_LIST ${CMAKE_PROPERTY_LIST})
        list(FILTER CMAKE_INTERFACE_PROPERTY_LIST INCLUDE REGEX "^((COMPATIBLE_)?INTERFACE|IMPORTED_LIBNAME_)_.*")
    endif()
    foreach(target Python::Module Python::Python Python3::Module Python3::Python)
        _python_utils_dump_vars_targets(${target} "${CMAKE_PROPERTY_LIST}")
    endforeach()
    foreach(target headers pybind11 module embed python_link_helper python_headers)
        _python_utils_dump_vars_targets("pybind11::${target}" "${CMAKE_INTERFACE_PROPERTY_LIST}")
    endforeach()

    get_cmake_property(vars VARIABLES)
    foreach(var ${vars})
        if (var MATCHES ".*(PYTHON|Python|PYBIND|Pybind).*" AND NOT var MATCHES ".*_COPYRIGHT$")
            message("${var}=${${var}}")
        endif ()
    endforeach()
endfunction()

function(python_utils_dump_vars_if_enabled _message)
    if($ENV{ARCTICDB_DEBUG_FIND_PYTHON})
        python_utils_dump_vars(${_message})
    endif()
endfunction()


# Checks
if(DEFINED CACHE{PYTHON_INCLUDE_DIRS})
    foreach(header_name Python.h pyconfig.h)
        find_file(valid_python_dir %{header_name} PATHS ${PYTHON_INCLUDE_DIRS} NO_DEFAULT_PATH)
        if(${valid_python_dir} STREQUAL "valid_python_dir-NOTFOUND")
            message(WARNING "PYTHON_INCLUDE_DIRS is supplied ('${PYTHON_INCLUDE_DIRS}'), but is invalid or incomplete\
                (missing ${header_name}). It will be ignored")
            unset(PYTHON_INCLUDE_DIRS CACHE)
            break()
        endif()
    endforeach()
endif()

foreach(var_name PYTHON_EXECUTABLE PYTHON_LIBRARIES PYTHON_LIBRARY PYTHON_INCLUDE_DIRS)
    if(DEFINED ${var_name})
        message("${var_name} is set (to ${${var_name}}), which can influence FindPython and Pybind.")
    endif()
endforeach ()

# Enhanced FindPython
if(DEFINED ARCTICDB_FIND_PYTHON_DEV_MODE)
    message("Using supplied ARCTICDB_FIND_PYTHON_DEV_MODE=${ARCTICDB_FIND_PYTHON_DEV_MODE}")
elseif(WIN32)
    set(ARCTICDB_FIND_PYTHON_DEV_MODE Development)
elseif(${CMAKE_VERSION} VERSION_LESS 3.15)
    execute_process(COMMAND cmake "-DPython_ROOT_DIR=${Python_ROOT_DIR}"
            "-DCMAKE_FIND_LIBRARY_PREFIXES=${CMAKE_FIND_LIBRARY_PREFIXES}"
            "-DCMAKE_FIND_LIBRARY_SUFFIXES=${CMAKE_FIND_LIBRARY_SUFFIXES}"
            -P "${CMAKE_CURRENT_SOURCE_DIR}/CMake/GetPythonDevelopmentConfig.cmake"
            OUTPUT_VARIABLE _guess_output)
    message(WARNING "Your cmake version is older than 3.15, which doesn't support the more granular FindPython \
            Development.Module component. Will try to user some heuristics:\n${_guess_output}")
    if(NOT DEFINED Python_INCLUDE_DIRS)
        string(REGEX REPLACE ".*Python_INCLUDE_DIRS=([^\n]*)\n.*" "\\1" Python_INCLUDE_DIRS ${_guess_output})
    endif()
    if(${_guess_output} MATCHES "-- Python_LIBRARY=[^\n]*\\.so\n.*")
        message("Found dynamic library, should be safe to use Development for Module linking")
        set(ARCTICDB_FIND_PYTHON_DEV_MODE Development)
    endif()
else()
    set(Python_USE_STATIC_LIBS ON)
    set(ARCTICDB_FIND_PYTHON_DEV_MODE Development.Module)
endif()

find_package(Python 3 COMPONENTS Interpreter ${ARCTICDB_FIND_PYTHON_DEV_MODE} REQUIRED)

# More checks
if(${BUILD_PYTHON_VERSION})
    if(NOT "${BUILD_PYTHON_VERSION}" VERSION_EQUAL "${Python_VERSION_MAJOR}.${Python_VERSION_MINOR}")
        message(FATAL_ERROR "You specified BUILD_PYTHON_VERSION=${BUILD_PYTHON_VERSION}, but FindPython found \
${Python_VERSION}. Use the official Python_ROOT_DIR and Python_EXECUTABLE hints to properly override the default Python,
or run cmake from within a virtualenv.")
    endif()
endif()
