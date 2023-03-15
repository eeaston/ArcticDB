# To avoid polluting the caller with a broken Python target, we try finding "Development" in a script
find_package(Python 3 COMPONENTS Interpreter Development)
message(STATUS "Python_INCLUDE_DIRS=${Python_INCLUDE_DIRS}")
message(STATUS "Python_LIBRARY=${Python_LIBRARY}")
