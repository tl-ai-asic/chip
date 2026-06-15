import os

os.environ.setdefault("CORE_VERSION", "v3")
os.environ.setdefault("EXPECT_LSU_PARALLEL", "1")
os.environ.setdefault("ENABLE_IPC_TESTS", "1")

from dv_lib.riscv_core import *  # noqa: F401,F403
