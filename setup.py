import os
import subprocess
import sys
import glob
import platform
import shutil
from pathlib import Path
from setuptools import setup, Command
from setuptools import Extension, find_packages
from setuptools.command.build_ext import build_ext
from setuptools.command.build_py import build_py
from setuptools.command.develop import develop
from wheel.bdist_wheel import bdist_wheel


class CompileProto(Command):
    description = '"protoc" generate code _pb2.py from .proto files'
    user_options = [("grpc-out-dir=", 'r', "See the docs of grpc_tools.protoc")]

    def initialize_options(self):
        self.grpc_out_dir = None

    def finalize_options(self):
        pass

    def run(self):
        print("\nProtoc compilation")
        cmd = [sys.executable, "-mgrpc_tools.protoc", "-Icpp/proto", "--python_out=python"]

        if self.grpc_out_dir:
            cmd.append(f"--grpc_python_out={self.grpc_out_dir}")

        cmd.extend(glob.glob("cpp/proto/arcticc/pb2/*.proto"))

        print(f"Running {cmd}")
        subprocess.check_output(cmd)
        if not os.path.exists("python/arcticc"):
            raise RuntimeError("Unable to locate Protobuf module during compilation.")
        else:
            open("python/arcticc/__init__.py", "a").close()
            open("python/arcticc/pb2/__init__.py", "a").close()


class CompileProtoAndBuild(build_py):
    def run(self):
        self.run_command("protoc")
        build_py.run(self)


class DevelopAndCompileProto(develop):
    def run(self):
        develop.run(self)
        self.run_command("protoc")  # compile after updating the deps


class CMakeExtension(Extension):
    def __init__(self, name, sourcedir=""):
        Extension.__init__(self, name, sources=[])
        self.sourcedir = os.path.abspath(sourcedir)


class CMakeBuild(build_ext):
    def run(self):
        for ext in self.extensions:
            self.build_extension(ext)

    def build_extension(self, ext):
        dest = self.get_ext_fullpath(ext.name)
        print(f"Destination: {dest}")

        install_dir = "cpp/out/install/"  # From CMakePresets.json
        env_var = "ARCTIC_CMAKE_PRESET"  # From CMakePresets.json
        preset = os.getenv(env_var, "*")
        if preset == "skip":
            return
        search = f"cpp/out/{preset}-build"
        candidates = glob.glob(search)
        if not candidates:
            cmake_check = subprocess.run("cmake -P cpp/CMake/CheckSupportsPreset.cmake", shell=True)
            # shell=True because cmake is an alias in the internal image
            if cmake_check.returncode != 0:
                artifact_name = self._configure_legacy_cmake("cpp/out/legacy-build", install_dir)
            else:
                artifact_name = self._configure_cmake_using_preset(preset, search, dest)
            candidates = glob.glob(search)

        assert len(candidates) == 1, f"Specify {env_var} or use a single build directory. {search}={candidates}"
        subprocess.check_call(["cmake", "--build", candidates[0], "--target", "arcticdb_ext"])
        subprocess.check_call(["cmake", "--install", candidates[0], "--component", "Python_Lib"])

        source = install_dir + artifact_name
        print(f"Moving {source} -> {dest}")
        shutil.move(source, dest)

    def _configure_cmake_using_preset(self, preset, search, dest):
        if preset == "*":
            suffix = "-debug" if self.debug else "-release"
            preset = ("windows-cl" if platform.system() == "Windows" else platform.system().lower()) + suffix
        print(
            f"Did not find build directory with '{search}'. Will configure and build using cmake preset {preset}",
            file=sys.stderr,
        )
        subprocess.check_call(["cmake", "-DTEST=NO", "--preset", preset], cwd="cpp")
        return os.path.basename(dest)

    def _configure_legacy_cmake(self, build_dir, install_dir):
        print("Legacy cmake configuration")
        env = {
            "TERM": "linux",  # to get colors
            "PATH": "/opt/gcc/8.2.0/bin:/opt/cmake/bin:/usr/bin:/usr/local/bin:/bin:/sbin:/usr/sbin:/usr/local/sbin",
            "CXX": "/opt/gcc/8.2.0/bin/g++",
            "CC": "/opt/gcc/8.2.0/bin/gcc",
        }
        if "MB_PYTHON_PLATFORM_NAME" in os.environ:
            python_root_dir = "/default-pegasus-venv"
        else:
            python_root_dir = Path(os.path.dirname(sys.executable)).parent

        python_version = f"{sys.version_info[0]}.{sys.version_info[1]}"

        process_args = [
            "cmake",
            "-DCMAKE_DEPENDS_USE_COMPILER=FALSE",
            f"-DPython_ROOT_DIR={python_root_dir}",
            f"-DBUILD_PYTHON_VERSION={python_version}",
            f"-DCMAKE_INSTALL_PREFIX={install_dir}",
            "-G",
            "CodeBlocks - Unix Makefiles",
            os.path.join(os.getcwd(), "cpp")
        ]

        if not os.path.exists(build_dir):
            os.makedirs(build_dir, mode=0o750)
        subprocess.check_call(process_args, env=env, cwd=build_dir)
        return "arcticdb_ext.so"


if __name__ == "__main__":
    setup(
        ext_modules=[CMakeExtension("arcticdb_ext")],
        package_dir={"": "python"},
        packages=find_packages(where="python", exclude=["tests", "tests.*"]),
        cmdclass=dict(
            build_ext=CMakeBuild,
            protoc=CompileProto,
            build_py=CompileProtoAndBuild,
            bdist_wheel=bdist_wheel,
            develop=DevelopAndCompileProto,
        ),
        zip_safe=False,
    )
