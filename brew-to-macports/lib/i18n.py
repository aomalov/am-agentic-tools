"""Message catalogue loader — python side.

Reads exactly the same ``locale/*.msg`` files as ``lib/i18n.sh``, so a string
exists once per language regardless of which half of the tool prints it.

Imported from the embedded report blocks like this::

    sys.path.insert(0, os.environ['I18N_LIB'])
    from i18n import t

    print(t('brew.nothing_to_do'))
    print(t('vendor.upgraded', name, old, new))

``t`` with extra arguments applies printf-style ``%`` formatting, which is what
the bash side uses too — keeping one placeholder syntax across both languages
and both halves.

Kept to python 3.9 syntax on purpose: the reports run on Apple's system
interpreter, which is 3.9 on current macOS and older on older releases.
"""

import os

_CAT = {}


def _load(path):
    try:
        fh = open(path, encoding='utf-8')
    except OSError:
        return
    with fh:
        for line in fh:
            line = line.rstrip('\n')
            s = line.strip()
            if not s or s.startswith('#') or '=' not in line:
                continue
            key, _, val = line.partition('=')
            key = key.strip()
            if not key:
                continue
            _CAT[key] = val.lstrip()


def init(directory=None, lang=None):
    """Load English as the base, then overlay the chosen language.

    A key the translation has not covered falls back to English rather than to
    an empty string, so a partial catalogue is still usable.
    """
    directory = directory or os.environ.get('I18N_DIR') or ''
    lang = lang or os.environ.get('I18N_LANG') or 'en'
    _CAT.clear()
    _load(os.path.join(directory, 'en.msg'))
    if lang != 'en':
        _load(os.path.join(directory, lang + '.msg'))
    return _CAT


def t(key, *args):
    """Translate. An unknown key renders as ``!key!`` so typos are visible."""
    s = _CAT.get(key)
    if s is None:
        s = '!%s!' % key
    if args:
        try:
            return s % args
        except (TypeError, ValueError):
            # A placeholder mismatch in one translation must not take the whole
            # report down; show the raw text and let the wrong line stand out.
            return s
    return s


# Importing is enough: the embedded blocks get their directory and language from
# the environment the shell already resolved.
init()
