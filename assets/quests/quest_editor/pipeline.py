"""Running one pipeline step, with what it printed captured."""
import contextlib
import io
import os
import runpy
import traceback


def _run(path, cwd):
    """A pipeline script, in this process, with what it printed captured.

    SystemExit is how 09_assemble.py says no - a stale fix, a row off the
    board - and its message is the useful half of this whole tool, so it is
    caught and shown rather than allowed to take the panel with it.

    stderr is captured too, or a warning and half a failure go to Houdini's
    console instead of to the panel that is showing you the run.
    """
    buf = io.StringIO()
    here = os.getcwd()
    try:
        os.chdir(cwd)
        with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
            runpy.run_path(path, run_name="__main__")
        return buf.getvalue().rstrip(), True
    except SystemExit as e:
        return (buf.getvalue() + "\n" + str(e)).strip(), False
    except Exception:
        return (buf.getvalue() + "\n" + traceback.format_exc()).strip(), False
    finally:
        os.chdir(here)
