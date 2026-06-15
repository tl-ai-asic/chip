import os

core_version = os.getenv("CORE_VERSION", "v3")
os.environ.setdefault("CORE_VERSION", core_version)
os.environ.setdefault("EXPECT_LSU_PARALLEL", "1" if core_version == "v3" else "0")
os.environ.setdefault("ENABLE_IPC_TESTS", "0")

from dv_lib.riscv_core import *  # noqa: F401,F403
