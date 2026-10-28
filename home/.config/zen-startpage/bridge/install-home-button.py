#!/usr/bin/env python3
"""Install/remove a fixed, local browser-chrome Home command through AutoConfig."""
from pathlib import Path
import argparse
import configparser
import shutil

MARKER = '// mrkvqv direct Home AutoConfig'
BOOTSTRAP = '''// mrkvqv direct Home AutoConfig preferences
pref("general.config.filename", "mrkvqv-home.cfg");
pref("general.config.obscure_value", 0);
pref("general.config.sandbox_enabled", false);
'''
CONFIG = '''// mrkvqv direct Home AutoConfig
// Load exactly one local profile script; no remote code or general script loader.
try {
  if (!Services.appinfo.inSafeMode) {
    Services.obs.addObserver(function(window) {
      try {
        const script = Services.dirsvc.get("ProfD", Components.interfaces.nsIFile);
        script.append("chrome"); script.append("zen-home.js");
        if (script.exists()) {
          const resources = Services.io.getProtocolHandler("resource").QueryInterface(Components.interfaces.nsIResProtocolHandler);
          resources.setSubstitution("mrkvqv-home", Services.io.newFileURI(script.parent));
          Services.scriptloader.loadSubScript("resource://mrkvqv-home/zen-home.js", window, "UTF-8");
        }
      } catch (error) { Components.utils.reportError(error); }
    }, "browser-delayed-startup-finished");
  }
} catch (error) { Components.utils.reportError(error); }
'''

def default_profile():
    base = Path.home() / 'Library/Application Support/zen'
    ini = configparser.ConfigParser()
    ini.read(base / 'profiles.ini')
    for section in ini.sections():
        if section.startswith('Install') and ini.has_option(section,'Default'):
            return (base / ini[section]['Default']).resolve()
    for section in ini.sections():
        if ini.get(section,'Default',fallback='') == '1' and ini.has_option(section,'Path'):
            return (base / ini[section]['Path']).resolve()
    raise SystemExit('Default Zen profile not found; pass --profile.')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile',type=Path)
    parser.add_argument('--app',type=Path,default=Path('/Applications/Zen.app'))
    parser.add_argument('--remove',action='store_true')
    args = parser.parse_args()
    profile = args.profile or default_profile()
    resources = args.app / 'Contents/Resources'
    if not profile.is_dir() or not (resources/'browser/omni.ja').is_file():
        raise SystemExit('Zen app or profile missing.')
    files = {resources/'defaults/pref/mrkvqv-home.js':BOOTSTRAP,resources/'mrkvqv-home.cfg':CONFIG}
    for path in files:
        if path.exists() and not path.read_text().startswith(MARKER):
            raise SystemExit('Refusing to replace an unrelated configuration: '+str(path))
    script = profile/'chrome/zen-home.js'
    if args.remove:
        for path in files:path.unlink(missing_ok=True)
        if script.exists() and script.read_text().startswith('// mrkvqv direct Home command.'):
            script.unlink()
        print('Direct Home loader removed; restart Zen.');return
    for path in (resources/'defaults/pref').glob('*.js'):
        if path not in files and 'general.config.filename' in path.read_text():
            raise SystemExit('Existing AutoConfig found; refusing to replace it: '+str(path))
    if script.exists() and not script.read_text().startswith('// mrkvqv direct Home command.'):
        raise SystemExit('Refusing to replace an unrelated zen-home.js.')
    for path,content in files.items():
        path.parent.mkdir(parents=True,exist_ok=True);path.write_text(content);path.chmod(0o644)
    script.parent.mkdir(parents=True,exist_ok=True)
    shutil.copyfile(Path(__file__).with_name('zen-home.js'),script);script.chmod(0o600)
    print('Direct Home loader installed; restart Zen.')

if __name__ == '__main__':main()
