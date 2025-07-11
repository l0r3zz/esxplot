#!/usr/bin/env python3
"""Bootstrap setuptools installation

If you want to use setuptools in your package's setup.py, just include this
file in the same directory with it, and add this to the top of your setup.py::

    from ez_setup import use_setuptools
    use_setuptools()

    from setuptools import setup
    setup(...)

This file can also be run as a script to install or upgrade setuptools.
"""
import sys
import re
import os
import urllib.request
import shutil
import hashlib

DEFAULT_VERSION = "0.6c9"
DEFAULT_URL = "http://pypi.python.org/packages/{}/s/setuptools/".format(sys.version[:3])

md5_data = {
    'setuptools-0.6b1-py2.3.egg': '8822caf901250d848b996b7f25c6e6ca',
    'setuptools-0.6b1-py2.4.egg': 'b79a8a403e4502fbb85ee3f1941735cb',
    'setuptools-0.6b2-py2.3.egg': '5657759d8a6d8fc44070a9d07272d99b',
    'setuptools-0.6b2-py2.4.egg': '4996a8d169d2be661fa32a6e52e4f82a',
    'setuptools-0.6b3-py2.3.egg': 'bb31c0fc7399a63579975cad9f5a0618',
    'setuptools-0.6b3-py2.4.egg': '38a8c6b3d6ecd22247f179f7da669fac',
    'setuptools-0.6b4-py2.3.egg': '62045a24ed4e1ebc77fe039aa4e6f7e5',
    'setuptools-0.6b4-py2.4.egg': '4cb2a185d228dacffb2d17f103b3b1c4',
    'setuptools-0.6c1-py2.3.egg': 'b3f2b5539d65cb7f74ad79127f1a908c',
    'setuptools-0.6c1-py2.4.egg': 'b45adeda0667d2d2ffe14009364f2a4b',
    'setuptools-0.6c2-py2.3.egg': 'f0064bf6aa2b7d0f3ba0b43f20817c27',
    'setuptools-0.6c2-py2.4.egg': '616192eec35f47e8ea16cd6a122b7277',
    'setuptools-0.6c3-py2.3.egg': 'f181fa125dfe85a259c9cd6f1d7b78fa',
    'setuptools-0.6c3-py2.4.egg': 'e0ed74682c998bfb73bf803a50e7b71e',
    'setuptools-0.6c3-py2.5.egg': 'abef16fdd61955514841c7c6bd98965e',
    'setuptools-0.6c4-py2.3.egg': 'b0b9131acab32022bfac7f44c5d7971f',
    'setuptools-0.6c4-py2.4.egg': '2a1f9656d4fbf3c97bf946c0a124e6e2',
    'setuptools-0.6c4-py2.5.egg': '8f5a052e32cdb9c72bcf4b5526f28afc',
    'setuptools-0.6c5-py2.3.egg': 'ee9fd80965da04f2f3e6b3576e9d8167',
    'setuptools-0.6c5-py2.4.egg': 'afe2adf1c01701ee841761f5bcd8aa64',
    'setuptools-0.6c5-py2.5.egg': 'a8d3f61494ccaa8714dfed37bccd3d5d',
    'setuptools-0.6c6-py2.3.egg': '35686b78116a668847237b69d549ec20',
    'setuptools-0.6c6-py2.4.egg': '3c56af57be3225019260a644430065ab',
    'setuptools-0.6c6-py2.5.egg': 'b2f8a7520709a5b34f80946de5f02f53',
    'setuptools-0.6c7-py2.3.egg': '209fdf9adc3a615e5115b725658e13e2',
    'setuptools-0.6c7-py2.4.egg': '5a8f954807d46a0fb67cf1f26c55a82e',
    'setuptools-0.6c7-py2.5.egg': '45d2ad28f9750e7434111fde831e8372',
    'setuptools-0.6c8-py2.3.egg': '50759d29b349db8cfd807ba8303f1902',
    'setuptools-0.6c8-py2.4.egg': 'cba38d74f7d483c06e9daa6070cce6de',
    'setuptools-0.6c8-py2.5.egg': '1721747ee329dc150590a58b3e1ac95b',
    'setuptools-0.6c9-py2.3.egg': 'a83c4020414807b496e4cfbe08507c03',
    'setuptools-0.6c9-py2.4.egg': '260a2be2e5388d66bdaee06abec6342a',
    'setuptools-0.6c9-py2.5.egg': 'fe67c3e5a17b12c0e7c541b7ea43a8e6',
    'setuptools-0.6c9-py2.6.egg': 'ca37b1ff16fa2ede6e19383e7b59245a',
}

import sys, os
import hashlib

def _validate_md5(egg_name, data):
    if egg_name in md5_data:
        digest = hashlib.md5(data).hexdigest()
        if digest != md5_data[egg_name]:
            print("md5 validation of {} failed!  (Possible download problem?)".format(egg_name), file=sys.stderr)
            sys.exit(2)
    return data

def use_setuptools(
    version=DEFAULT_VERSION, download_base=DEFAULT_URL, to_dir=os.curdir,
    download_delay=15
):
    """Automatically find/download setuptools and make it available on sys.path

    `version` should be a valid setuptools version number that is available
    as an egg for download under the `download_base` URL (which should end with
    a '/').  `to_dir` is the directory where setuptools will be downloaded, if
    it is not already available.  If `download_delay` is specified, it should
    be the number of seconds that will be paused before initiating a download,
    should one be required.  If an older version of setuptools is installed,
    this routine will print a message to ``sys.stderr`` and raise SystemExit in
    an attempt to abort the calling script.
    """
    was_imported = 'pkg_resources' in sys.modules or 'setuptools' in sys.modules
    def do_download():
        egg = download_setuptools(version, download_base, to_dir, download_delay)
        sys.path.insert(0, egg)
        import setuptools; setuptools.bootstrap_install_from = egg
    try:
        import pkg_resources
    except ImportError:
        return do_download()       
    try:
        pkg_resources.require("setuptools>="+version); return
    except pkg_resources.VersionConflict as e:
        if was_imported:
            print("The required version of setuptools (>={}) is not available, and\n"
                  "can't be installed while this script is running. Please install\n"
                  " a more recent version first, using 'easy_install -U setuptools'."
                  "\n\n(Currently using {})".format(version, e.args[0]), file=sys.stderr)
            sys.exit(2)
        else:
            del pkg_resources, sys.modules['pkg_resources']    # reload ok
            return do_download()
    except pkg_resources.DistributionNotFound:
        return do_download()

def download_setuptools(
    version=DEFAULT_VERSION, download_base=DEFAULT_URL, to_dir=os.curdir,
    delay = 15
):
    """Download setuptools from a specified location and return its filename

    `version` should be a valid setuptools version number that is available
    as an egg for download under the `download_base` URL (which should end
    with a '/'). `to_dir` is the directory where the egg will be downloaded.
    `delay` is the number of seconds to pause before an actual download attempt.
    """
    import urllib.request, shutil
    egg_name = "setuptools-{}-py{}.egg".format(version,sys.version[:3])
    url = download_base + egg_name
    saveto = os.path.join(to_dir, egg_name)
    src = dst = None
    if not os.path.exists(saveto):  # Avoid repeated downloads
        try:
            import logging
            if delay:
                logging.warning("""
---------------------------------------------------------------------------
This script requires setuptools version {} to run (even to display
help).  I will attempt to download it for you (from
{}), but
you may need to enable firewall access for this script first.
I will start the download in {} seconds.

(Note: if this machine does not have network access, please obtain the file

   {}

and place it in this directory before rerunning this script.)
---------------------------------------------------------------------------""".format(version, download_base, delay, url))
                import time
                time.sleep(delay)
            logging.warning("Downloading {}".format(url))
            src = urllib.request.urlopen(url)
            # Read/write all in one block, so we don't create a corrupt file
            # if the download is interrupted.
            data = _validate_md5(egg_name, src.read())
            with open(saveto, 'wb') as dst:
                dst.write(data)
        finally:
            if src: src.close()
            if dst: dst.close()
    return os.path.realpath(saveto)

def main(argv, version=DEFAULT_VERSION):
    """Install or upgrade setuptools and EasyInstall"""
    try:
        import setuptools
    except ImportError:
        egg = None
        try:
            egg = download_setuptools(version, delay=0)
            sys.path.insert(0,egg)
            from setuptools.command.easy_install import main
            return main(list(argv)+[egg])   # we're done here
        finally:
            if egg and os.path.exists(egg):
                os.unlink(egg)
    else:
        if setuptools.__version__ == '0.0.1':
            print("You have an obsolete version of setuptools installed.  Please\n"
                  "remove it from your system entirely before rerunning this script.", file=sys.stderr)
            sys.exit(2)

    req = "setuptools>="+version
    import pkg_resources
    try:
        pkg_resources.require(req)
    except (pkg_resources.VersionConflict, pkg_resources.DistributionNotFound) as e:
        try:
            from setuptools.command.easy_install import main
        except (ImportError, SyntaxError) as e:
            from setuptools.command.easy_install import main
        main(list(argv)+[download_setuptools(delay=0)])
        sys.exit(0) # try to force an exit
    else:
        if argv:
            from setuptools.command.easy_install import main
            main(argv)
        else:
            print("Setuptools version {} or greater has been installed.".format(version))
            print('Run "ez_setup.py -U setuptools" to reinstall or upgrade.')

def update_md5(filenames):
    """Update our built-in md5 registry"""

    import re
    import hashlib

    for name in filenames:
        base = os.path.basename(name)
        with open(name, 'rb') as f:
            md5_data[base] = hashlib.md5(f.read()).hexdigest()

    data = ["    {}:{}\n".format(repr(it[0]), repr(it[1])) for it in md5_data.items()]
    data.sort()
    repl = "".join(data)

    import inspect
    srcfile = inspect.getsourcefile(sys.modules[__name__])
    with open(srcfile, 'r') as f:
        src = f.read()

    match = re.search("\nmd5_data = {\n([^}]+)}", src)
    if not match:
        print("Internal error!", file=sys.stderr)
        sys.exit(2)

    src = src[:match.start(1)] + repl + src[match.end(1):]
    with open(srcfile, 'w') as f:
        f.write(src)


if __name__=='__main__':
    if len(sys.argv)>2 and sys.argv[1]=='--md5update':
        update_md5(sys.argv[2:])
    else:
        main(sys.argv[1:])






